import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
import '../providers/sync_provider.dart';
import '../services/background_sync_service.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../services/ubicacion_service.dart';
import 'agregar_contacto_screen.dart';
import 'acerca_de_screen.dart';
import 'caller_id_screen.dart';
import 'contacto_detalle_screen.dart';
import 'escanear_agenda_screen.dart';
import 'invitacion_screen.dart';
import 'lista_negra_screen.dart';
import 'login_admin_screen.dart';
import 'mis_reportes_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _localDb = LocalDatabaseService();
  final _supabaseService = SupabaseService();

  List<Contacto> _visibles = [];
  List<Contacto> _favoritos = [];
  List<Map<String, dynamic>> _categorias = [];
  String? _categoriaFiltro;
  String? _provinciaFiltro;
  String? _municipioFiltro;
  bool _cargando = true;
  bool _online = true;
  DateTime? _ultimaSync;
  int _filtrosActivos = 0;
  static const _pageSize = 50;
  int _paginaActual = 1;
  int _totalContactos = 0;
  bool _cargandoMas = false;
  final _scrollController = ScrollController();
  StreamSubscription? _connectivitySub;

  // Estado de sincronización
  bool _sincronizando = false;
  int _syncDescargados = 0;
  int _syncTotal = 0;

  @override
  void initState() {
    super.initState();
    _cargarContactos();
    _cargarCategorias();
    _sincronizar();
    _verificarActualizacion();
    _actualizarFlagsReportes(); // ← actualizar tiene_reportes en SQLite al arrancar
    _scrollController.addListener(_onScroll);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _online = result != ConnectivityResult.none);
      if (_online) _sincronizar();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pedirPermisoNotificaciones();
      // Escuchar sync completada O con error parcial para recargar contactos locales
      ref.listenManual(syncProvider, (prev, next) {
        final termino = next.estado == SyncEstado.completado ||
            next.estado == SyncEstado.error ||
            next.estado == SyncEstado.cancelado;
        final prevTermino = prev?.estado == SyncEstado.completado ||
            prev?.estado == SyncEstado.error ||
            prev?.estado == SyncEstado.cancelado;
        if (termino && !prevTermino && next.descargados > 0) {
          _recargarPagina();
        }
      });
    });
  }

  Future<void> _pedirPermisoNotificaciones() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // permission_handler puede no tener notification en versiones viejas — ignorar
    }
  }

  /// Actualiza tiene_reportes en SQLite consultando Supabase al arrancar.
  /// Garantiza que la lista negra funcione aunque la sync esté incompleta.
  Future<void> _actualizarFlagsReportes() async {
    try {
      if (!_online) return;
      final ids = await _supabaseService.getContactosConReportes();
      await _localDb.actualizarReportesEficiente(ids);
    } catch (_) {
      // Silencioso — no crítico para el arranque
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _verificarActualizacion() async {
    _buscarActualizacion(manual: false);
  }

  Future<void> _buscarActualizacion({bool manual = false}) async {
    final updateService = UpdateService();
    final update = await updateService.checkForUpdate();
    if (!mounted) return;

    if (update != null) {
      UpdateService.showUpdateDialog(context, update);
    } else if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Ya tienes la última versión')),
      );
    }
  }

  Future<void> _cargarContactos() async {
    setState(() => _cargando = true);
    try {
      _ultimaSync = await _localDb.getUltimaSincronizacion();
      final favIds = await _localDb.getFavoritosIds();
      final favoritos = favIds.isNotEmpty
          ? await _localDb.getContactosPorIds(favIds)
          : <Contacto>[];
      // Respetar filtros activos al recargar
      final totalContactos = await _localDb.countContactos(
        categoriaId: _categoriaFiltro == '_reportados' ? null : _categoriaFiltro,
        provincia: _provinciaFiltro,
        municipio: _municipioFiltro,
        soloReportados: _categoriaFiltro == '_reportados',
      );
      final primeraPagena = await _localDb.getContactosPaginados(
        offset: 0,
        limit: _pageSize,
        categoriaId: _categoriaFiltro == '_reportados' ? null : _categoriaFiltro,
        provincia: _provinciaFiltro,
        municipio: _municipioFiltro,
        soloReportados: _categoriaFiltro == '_reportados',
      );
      if (mounted) {
        setState(() {
          _totalContactos = totalContactos;
          _visibles = primeraPagena;
          _favoritos = favoritos;
          _paginaActual = 1;
        });
      }
    } catch (e) {
      debugPrint('_cargarContactos error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _resincronizarTodo() async {
    final syncState = ref.read(syncProvider);
    if (syncState.enProgreso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ Sincronización en curso — espera o cancela desde el banner')),
      );
      return;
    }
    await BackgroundSyncService.iniciarSync(ref);
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    final syncState = ref.read(syncProvider);
    if (syncState.enProgreso) return;

    setState(() { _sincronizando = true; _syncDescargados = 0; _syncTotal = 0; });

    try {
      final ultimaSync  = await _localDb.getUltimaSincronizacion();
      final totalRemoto = await _supabaseService.contarContactosAprobados();
      final totalLocal  = await _localDb.countContactos();
      final desfase     = totalRemoto - totalLocal;

      debugPrint('SYNC: remoto=$totalRemoto local=$totalLocal desfase=$desfase ultimaSync=$ultimaSync');

      if (desfase > 50 || ultimaSync == null) {
        debugPrint('SYNC: iniciando background service (desfase grande o primera vez)');
        if (mounted) setState(() => _sincronizando = false);
        await BackgroundSyncService.iniciarSync(ref);
        return;
      }

      debugPrint('SYNC: sync incremental (desfase=$desfase)');
      // Sync incremental rápida
      final nuevos = await _supabaseService.getContactosAprobadosDesde(ultimaSync);
      if (nuevos.isNotEmpty) await _localDb.sincronizarBatch(nuevos);
      final eliminados = await _supabaseService.getContactosEliminadosDesde(ultimaSync);
      for (final id in eliminados) await _localDb.eliminarContacto(id);
      final ids = await _supabaseService.getContactosConReportes();
      await _localDb.actualizarReportesEficiente(ids);
      await _localDb.guardarUltimaSincronizacion(DateTime.now());
      await _recargarPagina();
    } catch (e) {
      debugPrint('Sync error: $e');
    }

    if (mounted) setState(() => _sincronizando = false);
  }

  Future<void> _cargarCategorias() async {
    try {
      final cats = await _supabaseService.getCategorias();
      setState(() => _categorias = cats);
      await _localDb.guardarCategorias(cats);
    } catch (_) {
      final catsLocal = await _localDb.getCategoriasLocal();
      setState(() => _categorias = catsLocal);
    }
  }

  void _aplicarFiltros() {
    _paginaActual = 1;
    _filtrosActivos = (_categoriaFiltro != null ? 1 : 0) +
        (_provinciaFiltro != null ? 1 : 0) +
        (_municipioFiltro != null ? 1 : 0);
    _recargarPagina();
  }

  Future<void> _recargarPagina() async {
    final query = _searchController.text;
    setState(() => _cargando = true);

    try {
      List<Contacto> resultado;
      int total;

      if (query.isNotEmpty) {
        resultado = await _localDb.buscarContactosPaginados(query, offset: 0, limit: _pageSize);
        final todos = await _localDb.buscarContactos(query);
        total = todos.length;
      } else {
        total = await _localDb.countContactos(
          categoriaId: _categoriaFiltro == '_reportados' ? null : _categoriaFiltro,
          provincia: _provinciaFiltro,
          municipio: _municipioFiltro,
          soloReportados: _categoriaFiltro == '_reportados',
        );
        resultado = await _localDb.getContactosPaginados(
          offset: 0,
          limit: _pageSize,
          categoriaId: _categoriaFiltro == '_reportados' ? null : _categoriaFiltro,
          provincia: _provinciaFiltro,
          municipio: _municipioFiltro,
          soloReportados: _categoriaFiltro == '_reportados',
        );
      }

      if (mounted) {
        setState(() {
          _visibles = resultado;
          _totalContactos = total;
          _paginaActual = 1;
        });
      }
    } catch (e) {
      debugPrint('_recargarPagina error: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || _visibles.length >= _totalContactos) return;
    setState(() => _cargandoMas = true);

    final query = _searchController.text;
    final offset = _paginaActual * _pageSize;
    List<Contacto> mas;

    if (query.isNotEmpty) {
      mas = await _localDb.buscarContactosPaginados(query, offset: offset, limit: _pageSize);
    } else {
      mas = await _localDb.getContactosPaginados(
        offset: offset,
        limit: _pageSize,
        categoriaId: _categoriaFiltro == '_reportados' ? null : _categoriaFiltro,
        provincia: _provinciaFiltro,
        municipio: _municipioFiltro,
        soloReportados: _categoriaFiltro == '_reportados',
      );
    }

    if (mounted) {
      setState(() {
        _visibles = [..._visibles, ...mas];
        _paginaActual++;
        _cargandoMas = false;
      });
    }
  }

  bool get _hayMas => _visibles.length < _totalContactos;

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _cargarMas();
    }
  }

  void _filtrar(String query) {
    _recargarPagina();
  }

  void _mostrarFiltros() {
    final provincias = UbicacionService.getProvincias();
    String? tempProvincia = _provinciaFiltro;
    String? tempMunicipio = _municipioFiltro;
    String? tempCategoria = _categoriaFiltro;
    List<String> municipiosDisponibles = tempProvincia != null
        ? UbicacionService.getMunicipios(tempProvincia)
        : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (ctx, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              controller: scrollController,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
                    TextButton(
                      onPressed: () {
                        setSheetState(() {
                          tempCategoria = null;
                          tempProvincia = null;
                          tempMunicipio = null;
                          municipiosDisponibles = [];
                        });
                      },
                      child: const Text('Limpiar todo'),
                    ),
                  ],
                ),
                const Divider(),

                // Categoría
                const SizedBox(height: 8),
                Text('Categoría', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempCategoria,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todas las categorías',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    const DropdownMenuItem(value: '_reportados', child: Text('⚠️ Reportados')),
                    ..._categorias.map((cat) => DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Text('${cat['icono'] ?? "📋"} ${cat['nombre']}'),
                    )),
                  ],
                  onChanged: (v) => setSheetState(() => tempCategoria = v),
                ),

                // Provincia
                const SizedBox(height: 16),
                Text('Provincia', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempProvincia,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todas las provincias',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todas')),
                    ...provincias.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                  ],
                  onChanged: (v) {
                    setSheetState(() {
                      tempProvincia = v;
                      tempMunicipio = null;
                      municipiosDisponibles = v != null ? UbicacionService.getMunicipios(v) : [];
                    });
                  },
                ),

                // Municipio
                const SizedBox(height: 16),
                Text('Municipio', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: tempMunicipio,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: 'Todos los municipios',
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...municipiosDisponibles.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                  ],
                  onChanged: (v) => setSheetState(() => tempMunicipio = v),
                ),

                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _categoriaFiltro = tempCategoria;
                      _provinciaFiltro = tempProvincia;
                      _municipioFiltro = tempMunicipio;
                    });
                    _aplicarFiltros();
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('APLICAR FILTROS'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _llamar(String telefono) async {
    final uri = Uri.parse('tel:$telefono');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Guía Telefónica'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _filtrosActivos > 0,
              label: Text('$_filtrosActivos'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filtros',
            onPressed: _mostrarFiltros,
          ),
          IconButton(
            icon: _sincronizando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar',
            onPressed: _sincronizando ? null : _sincronizar,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              final syncEnProgreso = ref.read(syncProvider).enProgreso;
              // Bloquear importar/exportar/resync durante sync en background
              if (syncEnProgreso && (value == 'resync')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⏳ Espera a que termine la sincronización')),
                );
                return;
              }
              switch (value) {
                case 'admin':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginAdminScreen()));
                  break;
                case 'update':
                  _buscarActualizacion(manual: true);
                  break;
                case 'resync':
                  _resincronizarTodo();
                  break;
                case 'callerid':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CallerIdScreen()));
                  break;
                case 'scan':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EscanearAgendaScreen()));
                  break;
                case 'listanegra':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ListaNegraScreen()));
                  break;
                case 'misreportes':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MisReportesScreen()));
                  break;
                case 'invitacion':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const InvitacionScreen()));
                  break;
                case 'about':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AcercaDeScreen()));
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'callerid', child: ListTile(leading: Icon(Icons.phone_callback), title: Text('Identificador de llamadas'), dense: true)),
              const PopupMenuItem(value: 'resync', child: ListTile(leading: Icon(Icons.cloud_download), title: Text('Resincronizar todo'), dense: true)),
              const PopupMenuItem(value: 'scan', child: ListTile(leading: Icon(Icons.security), title: Text('Escanear agenda'), dense: true)),
              const PopupMenuItem(value: 'listanegra', child: ListTile(leading: Icon(Icons.warning_amber, color: Colors.red), title: Text('Lista Negra'), dense: true)),
              const PopupMenuItem(value: 'misreportes', child: ListTile(leading: Icon(Icons.flag, color: Colors.orange), title: Text('Mis Reportes'), dense: true)),
              const PopupMenuItem(value: 'invitacion', child: ListTile(leading: Icon(Icons.card_giftcard, color: Colors.purple), title: Text('Mis invitaciones'), dense: true)),
              const PopupMenuItem(value: 'update', child: ListTile(leading: Icon(Icons.system_update), title: Text('Buscar actualización'), dense: true)),
              const PopupMenuItem(value: 'admin', child: ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('Panel Admin'), dense: true)),
              const PopupMenuItem(value: 'about', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Acerca de'), dense: true)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner offline
          if (!_online)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.shade700,
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Sin conexión — mostrando datos locales', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),

          // Banner de progreso de sincronización
          if (_sincronizando && _syncTotal > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF0284C7),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sincronizando... $_syncDescargados / $_syncTotal',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${(_syncTotal > 0 ? (_syncDescargados * 100 / _syncTotal).toStringAsFixed(0) : '0')}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _syncTotal > 0 ? _syncDescargados / _syncTotal : 0,
                      minHeight: 4,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else if (_sincronizando && _syncTotal == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF0284C7),
              child: const Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  SizedBox(width: 10),
                  Text('Verificando cambios...', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),

          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar contacto...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _aplicarFiltros();
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: _filtrar,
            ),
          ),

          // Chips de filtros activos
          if (_filtrosActivos > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  if (_categoriaFiltro == '_reportados')
                    Chip(
                      label: const Text('⚠️ Reportados', style: TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _categoriaFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    )
                  else if (_categoriaFiltro != null)
                    Chip(
                      label: Text(_categorias.firstWhere((c) => c['id'] == _categoriaFiltro, orElse: () => {'nombre': '?'})['nombre'] ?? '?', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _categoriaFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_provinciaFiltro != null)
                    Chip(
                      label: Text('🗺 $_provinciaFiltro', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() { _provinciaFiltro = null; _municipioFiltro = null; }); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (_municipioFiltro != null)
                    Chip(
                      label: Text('🏘 $_municipioFiltro', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () { setState(() => _municipioFiltro = null); _aplicarFiltros(); },
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),

          // Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              children: [
                Text('$_totalContactos contactos', style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                if (_ultimaSync != null)
                  Text('Sync: ${_formatearFecha(_ultimaSync!)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),

          // Favoritos
          if (_favoritos.isNotEmpty && _searchController.text.isEmpty && _filtrosActivos == 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('⭐ Favoritos', style: Theme.of(context).textTheme.titleSmall),
                ),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _favoritos.length,
                    itemBuilder: (ctx, i) {
                      final c = _favoritos[i];
                      return GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: c))).then((_) => _cargarContactos()),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.only(right: 8),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(c.nombreCompleto, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(c.telefono, style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
              ],
            ),

          // Lista de contactos
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _visibles.isEmpty
                    ? const Center(child: Text('No se encontraron contactos'))
                    : RefreshIndicator(
                        onRefresh: _sincronizar,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _visibles.length + (_hayMas ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _visibles.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return _ContactoCard(
                              contacto: _visibles[index],
                              onLlamar: _llamar,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AgregarContactoScreen()),
          );
          if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Contacto enviado para aprobación')),
            );
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final diff = DateTime.now().difference(fecha);
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }
}

class _ContactoCard extends StatelessWidget {
  final Contacto contacto;
  final Function(String) onLlamar;

  const _ContactoCard({required this.contacto, required this.onLlamar});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: contacto)),
        ),
        leading: Hero(
          tag: 'avatar_${contacto.id}',
          child: CircleAvatar(
            backgroundColor: contacto.tieneReportes
                ? (contacto.reporteConfirmado ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2))
                : null,
            child: contacto.tieneReportes
                ? Icon(Icons.warning_amber, color: contacto.reporteConfirmado ? Colors.red : Colors.orange, size: 20)
                : Text(
                    contacto.nombre[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        title: Text(contacto.nombreCompleto),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📱 ${contacto.telefono}'),
            if (contacto.ubicacionCompleta != null)
              Text('📍 ${contacto.ubicacionCompleta}', style: Theme.of(context).textTheme.bodySmall),
            if (contacto.categoriaNombre != null)
              Text('${contacto.categoriaIcono ?? "📂"} ${contacto.categoriaNombre}',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.phone, color: Colors.green),
          onPressed: () => onLlamar(contacto.telefono),
        ),
        isThreeLine: true,
      ),
    );
  }
}

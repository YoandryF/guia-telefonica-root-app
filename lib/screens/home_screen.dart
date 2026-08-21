import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/contacto.dart';
import '../providers/filtros_provider.dart';
import '../providers/contactos_provider.dart';
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

  // Estado local que se mantiene (no está en providers)
  List<Contacto> _favoritos = [];
  List<Map<String, dynamic>> _categorias = [];
  // _provinciaFiltro y _municipioFiltro migrados a filtrosProvider
  bool _online = true;
  DateTime? _ultimaSync;
  final _scrollController = ScrollController();
  StreamSubscription? _connectivitySub;

  // Acumulador local para scroll infinito (el provider reemplaza páginas, no acumula)
  List<Contacto> _contactosAcumulados = [];
  int _ultimaPaginaCargada = -1;

  // Estado de sincronización (legacy — se mantiene para la sync incremental manual)
  bool _sincronizando = false;
  int _syncDescargados = 0;
  int _syncTotal = 0;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    _cargarFavoritos();
    _cargarUltimaSync();
    _verificarActualizacion();
    _scrollController.addListener(_onScroll);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final connectivityList = result;
      setState(() => _online = !connectivityList.contains(ConnectivityResult.none));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pedirPermisoNotificaciones();
      // Escuchar sync completada para recargar contactos
      ref.listenManual(syncProvider, (prev, next) {
        final termino = next.estado == SyncEstado.completado ||
            next.estado == SyncEstado.error ||
            next.estado == SyncEstado.cancelado;
        final prevTermino = prev?.estado == SyncEstado.completado ||
            prev?.estado == SyncEstado.error ||
            prev?.estado == SyncEstado.cancelado;
        if (termino && !prevTermino && next.descargados > 0) {
          _resetAcumulador();
          ref.read(contactosProvider.notifier).recargar();
          _cargarFavoritos();
        }
      });
      // Escuchar cambios en filtros para resetear el acumulador
      ref.listenManual(filtrosProvider, (prev, next) {
        if (prev != next) {
          _resetAcumulador();
          ref.read(contactosProvider.notifier).recargar();
        }
      });
    });
  }

  void _resetAcumulador() {
    setState(() {
      _contactosAcumulados = [];
      _ultimaPaginaCargada = -1;
    });
  }

  Future<void> _cargarFavoritos() async {
    final favIds = await _localDb.getFavoritosIds();
    final favoritos = favIds.isNotEmpty
        ? await _localDb.getContactosPorIds(favIds)
        : <Contacto>[];
    if (mounted) setState(() => _favoritos = favoritos);
  }

  Future<void> _cargarUltimaSync() async {
    _ultimaSync = await _localDb.getUltimaSincronizacion();
    if (mounted) setState(() {});
  }

  Future<void> _pedirPermisoNotificaciones() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  Future<void> _actualizarFlagsReportes() async {
    try {
      if (!_online) return;
      final ids = await _supabaseService.getContactosConReportes();
      await _localDb.actualizarReportesEficiente(ids);
    } catch (_) {}
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

  Future<void> _resincronizarTodo() async {
    final syncState = ref.read(syncProvider);
    if (syncState.enProgreso) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⏳ Sincronización en curso — espera o cancela desde el banner')),
        );
      }
      return;
    }
    // Usar unawaited para no bloquear si el widget se desmonta
    BackgroundSyncService.iniciarSync(ref).catchError((e) {
      debugPrint('resync error: $e');
    });
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
      final nuevos = await _supabaseService.getContactosAprobadosDesde(ultimaSync);
      if (nuevos.isNotEmpty) await _localDb.sincronizarBatch(nuevos);
      final eliminados = await _supabaseService.getContactosEliminadosDesde(ultimaSync);
      for (final id in eliminados) {
        await _localDb.eliminarContacto(id);
      }
      final ids = await _supabaseService.getContactosConReportes();
      await _localDb.actualizarReportesEficiente(ids);
      await _localDb.guardarUltimaSincronizacion(DateTime.now());
      _cargarUltimaSync();
      // Recargar contactos via provider
      _resetAcumulador();
      ref.read(contactosProvider.notifier).recargar();
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

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _cargarMasPaginas();
    }
  }

  Future<void> _cargarMasPaginas() async {
    final contactosAsync = ref.read(contactosProvider);
    final contactosState = contactosAsync.valueOrNull;
    if (contactosState == null) return;
    if (contactosState.loading) return;  // ya está cargando más
    if (_contactosAcumulados.length >= contactosState.total) return;
    if (contactosAsync.isLoading) return;

    await ref.read(contactosProvider.notifier).siguientePagina();
  }

  void _onSearchChanged(String query) {
    ref.read(filtrosProvider.notifier).setQuery(query);
  }

  void _limpiarBusqueda() {
    _searchController.clear();
    ref.read(filtrosProvider.notifier).setQuery('');
  }

  void _aplicarFiltrosLocales() {
    // Resetear acumulador ya que los filtros cambiaron
    _resetAcumulador();
    // Los filtros de provincia/municipio aún no están en el provider,
    // así que forzamos una recarga del provider (que usa categoría y soloReportados)
    ref.read(contactosProvider.notifier).recargar();
  }

  int get _filtrosActivos {
    final filtros = ref.read(filtrosProvider);
    return filtros.contadorFiltrosActivos;
  }

  void _mostrarFiltros() {
    final provincias = UbicacionService.getProvincias();
    final filtrosState = ref.read(filtrosProvider);
    String? tempProvincia = filtrosState.provincia;  // ← desde provider
    String? tempMunicipio = filtrosState.municipio;  // ← desde provider
    String? tempCategoria = filtrosState.categoriaId;
    bool tempSoloReportados = filtrosState.soloReportados;
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
                          tempSoloReportados = false;
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
                  value: tempSoloReportados ? '_reportados' : tempCategoria,
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
                  onChanged: (v) => setSheetState(() {
                    if (v == '_reportados') {
                      tempCategoria = null;
                      tempSoloReportados = true;
                    } else {
                      tempCategoria = v;
                      tempSoloReportados = false;
                    }
                  }),
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
                    // Aplicar filtros al provider
                    if (tempSoloReportados) {
                      ref.read(filtrosProvider.notifier).setCategoria(null);
                      if (!ref.read(filtrosProvider).soloReportados) {
                        ref.read(filtrosProvider.notifier).toggleSoloReportados();
                      }
                    } else {
                      if (ref.read(filtrosProvider).soloReportados) {
                        ref.read(filtrosProvider.notifier).toggleSoloReportados();
                      }
                      ref.read(filtrosProvider.notifier).setCategoria(tempCategoria);
                    }
                    // Provincia y municipio ahora en el provider — activan filtro real en SQLite
                    ref.read(filtrosProvider.notifier).setProvincia(tempProvincia);
                    ref.read(filtrosProvider.notifier).setMunicipio(tempMunicipio);
                    _resetAcumulador();
                    ref.read(contactosProvider.notifier).recargar();
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
    // Observar providers
    final filtrosState = ref.watch(filtrosProvider);
    final contactosAsync = ref.watch(contactosProvider);
    // contactosFiltradosProvider filtra en memoria — solo útil para listas pequeñas
    // Para búsqueda real usamos busquedaContactosProvider con FTS5
    // final contactosFiltrados = ref.watch(contactosFiltradosProvider);

    // Derivar estado del provider
    final int filtrosActivosCount = _filtrosActivos;
    // cargando = spinner central, solo cuando no hay nada que mostrar todavía
    final bool cargando = contactosAsync.isLoading && _contactosAcumulados.isEmpty;
    // cargandoMas = spinner al final de lista (scroll infinito)
    final bool cargandoMas = contactosAsync.valueOrNull?.loading == true;
    final int totalContactos = contactosAsync.valueOrNull?.total ?? 0;

    // Acumular contactos para scroll infinito
    contactosAsync.whenData((state) {
      // Siempre reemplazar en página 0 (nueva búsqueda o filtro aplicado)
      // Acumular solo en páginas > 0 (scroll infinito)
      final esPrimeraPagina = state.paginaActual == 0;
      final esNuevaPagina   = state.paginaActual > _ultimaPaginaCargada;

      if (esPrimeraPagina || esNuevaPagina) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              if (esPrimeraPagina) {
                // Reemplazar siempre — puede ser 0 contactos si el filtro no tiene resultados
                _contactosAcumulados = List.from(state.contactos);
              } else {
                _contactosAcumulados = [..._contactosAcumulados, ...state.contactos];
              }
              _ultimaPaginaCargada = state.paginaActual;
            });
          }
        });
      }
    });

    // Determinar qué contactos mostrar
    final List<Contacto> visibles;
    if (filtrosState.query.isNotEmpty) {
      final busquedaAsync = ref.watch(busquedaContactosProvider(BusquedaParams(
        query:          filtrosState.query,
        categoriaId:    filtrosState.categoriaId,
        provincia:      filtrosState.provincia,
        municipio:      filtrosState.municipio,
        soloReportados: filtrosState.soloReportados,
      )));
      visibles = busquedaAsync.when(
        data: (lista) => lista,
        loading: () => [],
        error: (_, __) => [],
      );
    } else {
      visibles = _contactosAcumulados;
    }

    final bool hayMas = visibles.length < totalContactos && filtrosState.query.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Guía Telefónica'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: filtrosActivosCount > 0,
              label: Text('$filtrosActivosCount'),
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
                case 'actualizar_reportes':
                  _actualizarFlagsReportes();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('🔄 Actualizando lista negra...')),
                  );
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
              const PopupMenuItem(value: 'actualizar_reportes', child: ListTile(leading: Icon(Icons.warning_amber, color: Colors.orange), title: Text('Actualizar lista negra'), dense: true)),
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
                        onPressed: _limpiarBusqueda,
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Chips de filtros activos
          if (filtrosActivosCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 6,
                children: [
                  if (filtrosState.soloReportados)
                    Chip(
                      label: const Text('⚠️ Reportados', style: TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        ref.read(filtrosProvider.notifier).toggleSoloReportados();
                        _aplicarFiltrosLocales();
                      },
                      visualDensity: VisualDensity.compact,
                    )
                  else if (filtrosState.categoriaId != null)
                    Chip(
                      label: Text(_categorias.firstWhere((c) => c['id'] == filtrosState.categoriaId, orElse: () => {'nombre': '?'})['nombre'] ?? '?', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        ref.read(filtrosProvider.notifier).setCategoria(null);
                        _aplicarFiltrosLocales();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (ref.watch(filtrosProvider).provincia != null)
                    Chip(
                      label: Text('🗺 ${ref.watch(filtrosProvider).provincia}', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        ref.read(filtrosProvider.notifier).setProvincia(null);
                        _resetAcumulador();
                        ref.read(contactosProvider.notifier).recargar();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  if (ref.watch(filtrosProvider).municipio != null)
                    Chip(
                      label: Text('🏘 ${ref.watch(filtrosProvider).municipio}', style: const TextStyle(fontSize: 11)),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        ref.read(filtrosProvider.notifier).setMunicipio(null);
                        _resetAcumulador();
                        ref.read(contactosProvider.notifier).recargar();
                      },
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
                Text('$totalContactos contactos', style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                if (_ultimaSync != null)
                  Text('Sync: ${_formatearFecha(_ultimaSync!)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),

          // Favoritos
          if (_favoritos.isNotEmpty && filtrosState.query.isEmpty && filtrosActivosCount == 0)
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
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: c))).then((_) {
                          _cargarFavoritos();
                          _resetAcumulador();
                          ref.read(contactosProvider.notifier).recargar();
                        }),
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
            child: cargando
                ? const Center(child: CircularProgressIndicator())
                : visibles.isEmpty
                    ? const Center(child: Text('No se encontraron contactos'))
                    : RefreshIndicator(
                        onRefresh: _sincronizar,
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: visibles.length + (hayMas || cargandoMas ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == visibles.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            return _ContactoCard(
                              contacto: visibles[index],
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
          if (result == true && mounted) {
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

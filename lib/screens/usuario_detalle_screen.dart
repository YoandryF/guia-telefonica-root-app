import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

class UsuarioDetalleScreen extends StatefulWidget {
  final String telegramUserId;
  const UsuarioDetalleScreen({super.key, required this.telegramUserId});

  @override
  State<UsuarioDetalleScreen> createState() => _UsuarioDetalleScreenState();
}

class _UsuarioDetalleScreenState extends State<UsuarioDetalleScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = SupabaseService();
  Map<String, dynamic> _data = {};
  bool _cargando = true;
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await _supabase.getUsuario360(widget.telegramUserId);
    setState(() {
      _data = data;
      _cargando = false;
    });
  }

  Map<String, dynamic> get _perfil => Map<String, dynamic>.from(_data['perfil'] ?? {});
  Map<String, dynamic> get _stats => Map<String, dynamic>.from(_data['stats'] ?? {});
  List<dynamic> get _restricciones => List.from(_data['restricciones'] ?? []);
  List<dynamic> get _reportes => List.from(_data['reportes'] ?? []);
  List<dynamic> get _avales => List.from(_data['avales'] ?? []);
  List<dynamic> get _contactos => List.from(_data['contactos'] ?? []);

  String get _nombre {
    final n = _perfil['nombre_display']?.toString() ?? '';
    if (n.isNotEmpty) return n;
    final u = _perfil['username']?.toString() ?? '';
    if (u.isNotEmpty) return '@$u';
    return widget.telegramUserId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_cargando ? 'Cargando...' : _nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                children: [
                  _buildHeader(),
                  _buildStatsRow(),
                  _buildRestricciones(),
                  const SizedBox(height: 8),
                  _buildTabs(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final nombre = _perfil['nombre_display']?.toString() ?? '';
    final username = _perfil['username']?.toString() ?? '';
    final chatId = _perfil['chat_id']?.toString() ?? widget.telegramUserId;
    final fechaRegistro = (_perfil['fecha_registro']?.toString() ?? '').split('T').first;
    final ultimaInteraccion = (_perfil['ultima_interaccion']?.toString() ?? '').split('T').first;
    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : (username.isNotEmpty ? username[0].toUpperCase() : '?');

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.teal.shade50,
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.teal.shade200,
            child: Text(inicial, style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          if (nombre.isNotEmpty)
            Text(nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (username.isNotEmpty)
            Text('@$username', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text('ID: $chatId', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (fechaRegistro.isNotEmpty) ...[
                const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Registro: $fechaRegistro', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 16),
              ],
              if (ultimaInteraccion.isNotEmpty) ...[
                const Icon(Icons.access_time, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Última: $ultimaInteraccion', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final reportes = (_stats['total_reportes'] as num?)?.toInt() ?? 0;
    final aprobados = (_stats['aprobados'] as num?)?.toInt() ?? 0;
    final desestimados = (_stats['desestimados'] as num?)?.toInt() ?? 0;
    final trust = (_stats['trust_pct'] as num?)?.toDouble() ?? 0;
    final avales = (_stats['total_avales'] as num?)?.toInt() ?? 0;
    final contactos = (_stats['total_contactos'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statChip('📣', '$reportes', 'Reportes'),
          _statChip('✅', '$aprobados', 'Aprob.'),
          _statChip('❌', '$desestimados', 'Desest.'),
          _statChip('⭐', '${trust.toStringAsFixed(0)}%', 'Trust'),
          _statChip('👍', '$avales', 'Avales'),
          _statChip('📇', '$contactos', 'Contactos'),
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String valor, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        Text(valor, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRestricciones() {
    final activas = _restricciones.where((r) => r['activo'] == true).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Restricciones (${activas.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton.icon(
                onPressed: _mostrarAgregarRestriccion,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (activas.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Sin restricciones activas', style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: activas.map((r) {
                final func = r['funcionalidad']?.toString() ?? '';
                final id = r['id']?.toString() ?? '';
                return Chip(
                  label: Text(_iconoFuncionalidad(func), style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _quitarRestriccion(id, func),
                  backgroundColor: Colors.red.shade50,
                  side: BorderSide(color: Colors.red.shade200),
                );
              }).toList(),
            ),
          const Divider(),
        ],
      ),
    );
  }

  String _iconoFuncionalidad(String func) {
    switch (func) {
      case 'reportar': return '📣 Reportar';
      case 'avalar': return '👍 Avalar';
      case 'reclamar': return '📝 Reclamar';
      case 'registrar': return '📇 Registrar';
      case 'ban_total': return '🚫 Ban total';
      default: return func;
    }
  }

  Future<void> _quitarRestriccion(String id, String func) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar restricción'),
        content: Text('¿Quitar restricción "$func" a este usuario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await _supabase.quitarRestriccion(id);
    if (mounted) {
      if (result['error'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Restricción eliminada')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['error']}')));
      }
    }
  }

  void _mostrarAgregarRestriccion() {
    String funcionalidad = 'reportar';
    final motivoController = TextEditingController();
    DateTime? fechaFin;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Agregar restricción', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: funcionalidad,
                decoration: const InputDecoration(
                  labelText: 'Funcionalidad',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'reportar', child: Text('📣 Reportar')),
                  DropdownMenuItem(value: 'avalar', child: Text('👍 Avalar')),
                  DropdownMenuItem(value: 'reclamar', child: Text('📝 Reclamar')),
                  DropdownMenuItem(value: 'registrar', child: Text('📇 Registrar')),
                  DropdownMenuItem(value: 'ban_total', child: Text('🚫 Ban total')),
                ],
                onChanged: (v) => setSheetState(() => funcionalidad = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      fechaFin != null
                          ? 'Hasta: ${fechaFin!.toIso8601String().split('T').first}'
                          : 'Sin fecha de fin (permanente)',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheetState(() => fechaFin = picked);
                    },
                    child: const Text('Elegir fecha'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (motivoController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Ingresa un motivo')),
                    );
                    return;
                  }
                  final adminEmail = Supabase.instance.client.auth.currentUser?.email ?? 'admin';
                  final result = await _supabase.agregarRestriccion(
                    telegramUserId: widget.telegramUserId,
                    funcionalidad: funcionalidad,
                    motivo: motivoController.text.trim(),
                    creadoPor: adminEmail,
                    fechaFin: fechaFin,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    if (result['error'] == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('✅ Restricción agregada')),
                      );
                      _cargar();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: ${result['error']}')),
                      );
                    }
                  }
                },
                child: const Text('Aplicar restricción'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return SizedBox(
      height: 400,
      child: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: '📣 Reportes'),
              Tab(text: '👍 Avales'),
              Tab(text: '📇 Contactos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildListaReportes(),
                _buildListaAvales(),
                _buildListaContactos(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaReportes() {
    if (_reportes.isEmpty) {
      return const Center(child: Text('Sin reportes', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _reportes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = Map<String, dynamic>.from(_reportes[i] as Map);
        final estado = r['estado']?.toString() ?? '';
        final contacto = r['contacto_nombre']?.toString() ?? '—';
        final motivo = r['motivo']?.toString() ?? '';
        final fecha = (r['fecha_reporte']?.toString() ?? '').split('T').first;

        final estadoIcon = estado == 'revisado' ? '✅' : estado == 'resuelto' ? '❌' : '⏳';
        return ListTile(
          dense: true,
          leading: Text(estadoIcon, style: const TextStyle(fontSize: 16)),
          title: Text(contacto, style: const TextStyle(fontSize: 13)),
          subtitle: Text(motivo, style: const TextStyle(fontSize: 11)),
          trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        );
      },
    );
  }

  Widget _buildListaAvales() {
    if (_avales.isEmpty) {
      return const Center(child: Text('Sin avales', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _avales.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = Map<String, dynamic>.from(_avales[i] as Map);
        final contacto = a['contacto_nombre']?.toString() ?? '—';
        final estado = a['estado']?.toString() ?? '';
        final fecha = (a['fecha']?.toString() ?? '').split('T').first;

        final estadoIcon = estado == 'aprobado' ? '✅' : estado == 'rechazado' ? '❌' : '⏳';
        return ListTile(
          dense: true,
          leading: Text(estadoIcon, style: const TextStyle(fontSize: 16)),
          title: Text(contacto, style: const TextStyle(fontSize: 13)),
          subtitle: Text(estado, style: const TextStyle(fontSize: 11)),
          trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        );
      },
    );
  }

  Widget _buildListaContactos() {
    if (_contactos.isEmpty) {
      return const Center(child: Text('Sin contactos', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _contactos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = Map<String, dynamic>.from(_contactos[i] as Map);
        final nombre = c['nombre']?.toString() ?? '—';
        final telefono = c['telefono']?.toString() ?? '';
        final estado = c['estado']?.toString() ?? '';
        final fecha = (c['fecha_creacion']?.toString() ?? '').split('T').first;

        return ListTile(
          dense: true,
          leading: const Icon(Icons.person, size: 18),
          title: Text(nombre, style: const TextStyle(fontSize: 13)),
          subtitle: Text('📱 $telefono  •  $estado', style: const TextStyle(fontSize: 11)),
          trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../repositories/contactos_repository.dart';
import '../repositories/usuarios_repository.dart';
import '../screens/contacto_detalle_screen.dart';

class UsuarioDetalleScreen extends StatefulWidget {
  final String telegramUserId;
  const UsuarioDetalleScreen({super.key, required this.telegramUserId});

  @override
  State<UsuarioDetalleScreen> createState() => _UsuarioDetalleScreenState();
}

class _UsuarioDetalleScreenState extends State<UsuarioDetalleScreen>
    with SingleTickerProviderStateMixin {
  final _usuariosRepo = UsuariosRepository();
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
    final data = await _usuariosRepo.getUsuario360(widget.telegramUserId);
    setState(() {
      _data = data;
      _cargando = false;
    });
  }

  // La RPC devuelve la clave "usuario" (no "perfil")
  Map<String, dynamic> get _usuario => Map<String, dynamic>.from(_data['usuario'] ?? {});
  Map<String, dynamic> get _stats   => Map<String, dynamic>.from(_data['stats']   ?? {});
  List<dynamic> get _restricciones  => List.from(_data['restricciones'] ?? []);
  List<dynamic> get _reportes        => List.from(_data['reportes']       ?? []);
  List<dynamic> get _avales          => List.from(_data['avales']          ?? []);
  List<dynamic> get _contactos       => List.from(_data['contactos']       ?? []);

  String get _nombreDisplay {
    final primer = _usuario['primer_nombre']?.toString() ?? '';
    final ultimo = _usuario['ultimo_nombre']?.toString()  ?? '';
    final nombre = '$primer $ultimo'.trim();
    if (nombre.isNotEmpty) return nombre;
    final user = _usuario['nombre_usuario']?.toString() ?? '';
    if (user.isNotEmpty) return '@$user';
    return widget.telegramUserId;
  }

  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_cargando ? 'Cargando...' : _nombreDisplay),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
        bottom: _cargando ? null : TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '📣 Reportes (${_reportes.length})'),
            Tab(text: '👍 Avales (${_avales.length})'),
            Tab(text: '📇 Contactos (${_contactos.length})'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _ScrollConHeader(
                  header: Column(children: [_buildHeader(), _buildStatsInteractivos(), _buildRestricciones()]),
                  child: _ListaReportes(reportes: _reportes, telegramUserId: widget.telegramUserId),
                ),
                _ScrollConHeader(
                  header: Column(children: [_buildHeader(), _buildStatsInteractivos(), _buildRestricciones()]),
                  child: _ListaAvales(avales: _avales, telegramUserId: widget.telegramUserId, onRefresh: _cargar),
                ),
                _ScrollConHeader(
                  header: Column(children: [_buildHeader(), _buildStatsInteractivos(), _buildRestricciones()]),
                  child: _ListaContactos(contactos: _contactos),
                ),
              ],
            ),
    );
  }

  // ─── Header ───────────────────────────────────────────────
  Widget _buildHeader() {
    final username  = _usuario['nombre_usuario']?.toString() ?? '';
    final chatId    = _usuario['chat_id']?.toString() ?? widget.telegramUserId;
    final fechaReg  = (_usuario['fecha_registro']?.toString() ?? '').split('T').first;
    final ultimaInt = (_usuario['ultima_interaccion']?.toString() ?? '').split('T').first;
    final inicial   = _nombreDisplay.isNotEmpty ? _nombreDisplay[0].toUpperCase() : '?';
    final baneado   = _stats['baneado'] == true;

    return Builder(builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Container(
        padding: const EdgeInsets.all(20),
        // Usa surface del tema — funciona en claro y oscuro
        color: scheme.surfaceContainerHighest,
        child: Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: baneado ? scheme.error : scheme.primary,
              child: Text(inicial, style: TextStyle(fontSize: 28, color: scheme.onPrimary, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            Text(_nombreDisplay,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface)),
            if (username.isNotEmpty)
              Text('@$username',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(chatId,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: scheme.onSurfaceVariant)),
            if (baneado)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('🚫 Baneado',
                    style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (fechaReg.isNotEmpty) ...[
                  Icon(Icons.calendar_today, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('Reg: $fechaReg',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 16),
              ],
              if (ultimaInt.isNotEmpty) ...[
                Icon(Icons.access_time, size: 12, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text('Últ: $ultimaInt',
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
    }); // Builder
  }

  // ─── Stats interactivos ───────────────────────────────────
  Widget _buildStatsInteractivos() {
    final totalRep    = (_stats['total_reportes']         as num?)?.toInt() ?? 0;
    final aprobados   = (_stats['reportes_aprobados']     as num?)?.toInt() ?? 0;
    final desestimados= (_stats['reportes_desestimados']  as num?)?.toInt() ?? 0;
    final trust       = (_stats['trust_pct']              as num?)?.toDouble();
    final totalAvales = (_stats['total_avales']           as num?)?.toInt() ?? 0;
    final avalesAprob = (_stats['avales_aprobados']       as num?)?.toInt() ?? 0;
    final totalCont   = (_stats['total_contactos']        as num?)?.toInt() ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          // Fila 1 — Reportes
          Row(
            children: [
              _statTap('📣', '$totalRep', 'Reportes', Colors.orange,
                  onTap: () { _tabs.animateTo(0); }),
              _statTap('✅', '$aprobados', 'Aprobados', Colors.green,
                  onTap: () => _verReportesFiltrados('revisado')),
              _statTap('❌', '$desestimados', 'Desestimados', Colors.red,
                  onTap: () => _verReportesFiltrados('resuelto')),
              _statTap('⭐', trust != null ? '${trust.toStringAsFixed(0)}%' : '—', 'Trust',
                  trust != null && trust >= 70 ? Colors.green : trust != null && trust >= 40 ? Colors.orange : Colors.red,
                  onTap: null),
            ],
          ),
          const SizedBox(height: 8),
          // Fila 2 — Avales y Contactos
          Row(
            children: [
              _statTap('👍', '$totalAvales', 'Avales', Colors.blue,
                  onTap: () { _tabs.animateTo(1); }),
              _statTap('✅', '$avalesAprob', 'Av. Aprobados', Colors.green,
                  onTap: () => _verAvalesFiltrados('aprobado')),
              _statTap('📇', '$totalCont', 'Contactos', Colors.purple,
                  onTap: () { _tabs.animateTo(2); }),
              _statTap('', '', '', Colors.transparent, onTap: null), // spacer
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTap(String emoji, String valor, String label, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: onTap != null ? 1 : 0,
          color: onTap != null ? null : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                if (emoji.isNotEmpty) Text(emoji, style: const TextStyle(fontSize: 16)),
                Text(valor, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey), textAlign: TextAlign.center),
                if (onTap != null)
                  const Icon(Icons.touch_app, size: 10, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _verReportesFiltrados(String estado) {
    final filtrados = _reportes.where((r) => (r as Map)['estado'] == estado).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ListaReportesSheet(
        reportes: filtrados,
        titulo: estado == 'revisado' ? '✅ Reportes aprobados' : '❌ Reportes desestimados',
      ),
    );
  }

  void _verAvalesFiltrados(String estado) {
    final filtrados = _avales.where((a) => (a as Map)['estado'] == estado).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ListaAvalesSheet(avales: filtrados, titulo: '✅ Avales aprobados'),
    );
  }

  // ─── Restricciones ────────────────────────────────────────
  Widget _buildRestricciones() {
    final activas = _restricciones.where((r) => (r as Map)['activo'] == true).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
              child: Text('Sin restricciones activas',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: activas.map((r) {
                final func = (r as Map)['funcionalidad']?.toString() ?? '';
                final id   = r['id']?.toString() ?? '';
                final motivo = r['motivo']?.toString() ?? '';
                return Tooltip(
                  message: motivo,
                  child: Chip(
                    label: Text(_labelFuncionalidad(func), style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => _quitarRestriccion(id, func),
                    backgroundColor: Colors.red.shade50,
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                );
              }).toList(),
            ),
          const Divider(),
        ],
      ),
    );
  }

  String _labelFuncionalidad(String func) {
    const map = {
      'reportar':  '📣 Reportar',
      'avalar':    '👍 Avalar',
      'reclamar':  '📝 Reclamar',
      'registrar': '📇 Registrar',
      'ban_total': '🚫 Ban total',
    };
    return map[func] ?? func;
  }

  Future<void> _quitarRestriccion(String id, String func) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar restricción'),
        content: Text('¿Quitar "$func" a este usuario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final result = await _usuariosRepo.quitarRestriccion(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(result['error'] == null ? '✅ Restricción eliminada' : 'Error: ${result['error']}'),
    ));
    if (result['error'] == null) _cargar();
  }

  void _mostrarAgregarRestriccion() {
    String funcionalidad = 'reportar';
    final motivoCtrl = TextEditingController();
    DateTime? fechaFin;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Agregar restricción',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: funcionalidad,
                decoration: const InputDecoration(labelText: 'Funcionalidad',
                    border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'reportar',  child: Text('📣 Reportar')),
                  DropdownMenuItem(value: 'avalar',    child: Text('👍 Avalar')),
                  DropdownMenuItem(value: 'reclamar',  child: Text('📝 Reclamar')),
                  DropdownMenuItem(value: 'registrar', child: Text('📇 Registrar')),
                  DropdownMenuItem(value: 'ban_total', child: Text('🚫 Ban total')),
                ],
                onChanged: (v) => setSt(() => funcionalidad = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(labelText: 'Motivo',
                    border: OutlineInputBorder(), isDense: true),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(
                    fechaFin != null
                        ? 'Hasta: ${fechaFin!.toIso8601String().split('T').first}'
                        : 'Sin fecha de fin (permanente)',
                    style: const TextStyle(fontSize: 12),
                  )),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSt(() => fechaFin = picked);
                    },
                    child: const Text('Elegir fecha'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (motivoCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Ingresa un motivo')));
                    return;
                  }
                  final adminEmail =
                      Supabase.instance.client.auth.currentUser?.email ?? 'admin';
                  final result = await _usuariosRepo.agregarRestriccion(
                    telegramUserId: widget.telegramUserId,
                    funcionalidad: funcionalidad,
                    motivo: motivoCtrl.text.trim(),
                    creadoPor: adminEmail,
                    fechaFin: fechaFin,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(result['error'] == null
                          ? '✅ Restricción aplicada'
                          : 'Error: ${result['error']}'),
                    ));
                    if (result['error'] == null) _cargar();
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
}

// ─────────────────────────────────────────────────────────────
// Wrapper: header + lista en un solo scroll
// ─────────────────────────────────────────────────────────────
class _ScrollConHeader extends StatelessWidget {
  final Widget header;
  final Widget child;
  const _ScrollConHeader({required this.header, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: header),
        SliverFillRemaining(
          hasScrollBody: true,
          child: child,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Lista de reportes (tab)
// ─────────────────────────────────────────────────────────────
class _ListaReportes extends StatelessWidget {
  final List<dynamic> reportes;
  final String telegramUserId;
  const _ListaReportes({required this.reportes, required this.telegramUserId});

  @override
  Widget build(BuildContext context) {
    if (reportes.isEmpty) {
      return const Center(child: Text('Sin reportes', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: reportes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) => _reporteTile(ctx, reportes[i] as Map),
    );
  }

  Widget _reporteTile(BuildContext ctx, Map r) {
    final estado    = r['estado']?.toString() ?? '';
    final contacto  = r['contacto_nombre']?.toString() ?? '—';
    final telefono  = r['contacto_telefono']?.toString() ?? '';
    final motivo    = r['motivo']?.toString() ?? '';
    final fecha     = (r['fecha_reporte']?.toString() ?? '').split('T').first;
    final nota      = r['nota_admin']?.toString() ?? '';
    final icon = estado == 'revisado' ? '✅' : estado == 'resuelto' ? '❌' : '⏳';

    return ListTile(
      dense: true,
      leading: Text(icon, style: const TextStyle(fontSize: 18)),
      title: Text(contacto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('📱 $telefono  •  $motivo', style: const TextStyle(fontSize: 11)),
          if (nota.isNotEmpty)
            Text('📝 $nota', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      // Tap → bottom sheet con detalle del reporte + botón al contacto
      onTap: () => _mostrarDetalleReporte(ctx, r),
    );
  }

  void _mostrarDetalleReporte(BuildContext ctx, Map r) {
    final estado   = r['estado']?.toString() ?? '';
    final contacto = r['contacto_nombre']?.toString() ?? '—';
    final telefono = r['contacto_telefono']?.toString() ?? '';
    final motivo   = r['motivo']?.toString() ?? '';
    final fecha    = (r['fecha_reporte']?.toString() ?? '').split('T').first;
    final nota     = r['nota_admin']?.toString() ?? '';
    final estadoLabel = estado == 'revisado' ? '✅ Aprobado' : estado == 'resuelto' ? '❌ Desestimado' : '⏳ Pendiente';
    final estadoColor = estado == 'revisado' ? Colors.green : estado == 'resuelto' ? Colors.red : Colors.orange;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // Título
            Row(
              children: [
                const Text('Detalle del reporte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: estadoColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: estadoColor.withOpacity(0.4)),
                  ),
                  child: Text(estadoLabel, style: TextStyle(color: estadoColor, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 24),
            // Datos
            _filaDetalle('👤 Contacto', contacto),
            _filaDetalle('📱 Teléfono', telefono),
            _filaDetalle('⚠️ Motivo', motivo),
            _filaDetalle('📅 Fecha', fecha),
            if (nota.isNotEmpty) _filaDetalle('📝 Nota admin', nota),
            const SizedBox(height: 20),
            // Botón ir al contacto
            if (telefono.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.person_search, size: 18),
                  label: Text('Ver contacto: $contacto'),
                  onPressed: () async {
                    Navigator.pop(ctx); // cerrar sheet
                    final c = await ContactosRepository().buscarPorTelefono(telefono);
                    if (c == null || !ctx.mounted) return;
                    Navigator.push(ctx, MaterialPageRoute(
                      builder: (_) => ContactoDetalleScreen(contacto: c),
                    ));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaDetalle(String label, String valor) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        Expanded(
          child: Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Lista de avales (tab) — con gestión admin inline
// ─────────────────────────────────────────────────────────────
class _ListaAvales extends StatelessWidget {
  final List<dynamic> avales;
  final String telegramUserId;
  final VoidCallback onRefresh;
  const _ListaAvales({required this.avales, required this.telegramUserId, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (avales.isEmpty) {
      return const Center(child: Text('Sin avales', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: avales.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) => _avalTile(ctx, avales[i] as Map),
    );
  }

  Widget _avalTile(BuildContext ctx, Map a) {
    final contacto = a['contacto_nombre']?.toString() ?? '—';
    final telefono = a['contacto_telefono']?.toString() ?? '';
    final estado   = a['estado']?.toString() ?? '';
    final fecha    = (a['fecha']?.toString() ?? '').split('T').first;
    final avalId   = a['id']?.toString() ?? '';
    final icon = estado == 'aprobado' ? '✅' : estado == 'rechazado' ? '❌' : '⏳';
    final esPendiente = estado == 'pendiente';

    return ListTile(
      dense: true,
      leading: Text(icon, style: const TextStyle(fontSize: 18)),
      title: Text(contacto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('📱 $telefono  •  $estado', style: const TextStyle(fontSize: 11)),
      trailing: esPendiente
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(width: 8),
                // Aprobar
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Aprobar',
                  onPressed: () => _resolverAval(ctx, avalId, 'aprobado'),
                ),
                const SizedBox(width: 4),
                // Rechazar
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Rechazar',
                  onPressed: () => _resolverAval(ctx, avalId, 'rechazado'),
                ),
              ],
            )
          : Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      onTap: telefono.isNotEmpty ? () => _abrirContacto(ctx, telefono) : null,
    );
  }

  Future<void> _resolverAval(BuildContext ctx, String avalId, String nuevoEstado) async {
    try {
      // TODO: mover a repositorio — resolver_aval RPC no tiene método en UsuariosRepository
      final r = await Supabase.instance.client.rpc('resolver_aval', params: {
        'p_aval_id':      avalId,
        'p_estado':       nuevoEstado,
        'p_revisado_por': Supabase.instance.client.auth.currentUser?.email ?? 'admin',
      });
      final result = r as Map?;
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(result?['ok'] == true
              ? (nuevoEstado == 'aprobado' ? '✅ Aval aprobado' : '❌ Aval rechazado')
              : 'Error: ${result?['error'] ?? 'desconocido'}'),
        ));
        if (result?['ok'] == true) onRefresh();
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _abrirContacto(BuildContext ctx, String telefono) async {
    final c = await ContactosRepository().buscarPorTelefono(telefono);
    if (c == null || !ctx.mounted) return;
    Navigator.push(ctx, MaterialPageRoute(
      builder: (_) => ContactoDetalleScreen(contacto: c),
    ));
  }
}

// ─────────────────────────────────────────────────────────────
// Lista de contactos (tab)
// ─────────────────────────────────────────────────────────────
class _ListaContactos extends StatelessWidget {
  final List<dynamic> contactos;
  const _ListaContactos({required this.contactos});

  @override
  Widget build(BuildContext context) {
    if (contactos.isEmpty) {
      return const Center(child: Text('Sin contactos', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: contactos.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) => _contactoTile(ctx, contactos[i] as Map),
    );
  }

  Widget _contactoTile(BuildContext ctx, Map c) {
    final nombre   = '${c['nombre'] ?? ''} ${c['apellido'] ?? ''}'.trim();
    final telefono = c['telefono']?.toString() ?? '';
    final estado   = c['estado']?.toString() ?? '';
    final fecha    = (c['fecha_creacion']?.toString() ?? '').split('T').first;
    final estadoIcon = estado == 'aprobado' ? '✅' : estado == 'pendiente' ? '⏳' : '❌';

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.purple.shade50,
        child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
            style: TextStyle(fontSize: 12, color: Colors.purple.shade700)),
      ),
      title: Text(nombre.isNotEmpty ? nombre : telefono,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('📱 $telefono  $estadoIcon $estado',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      onTap: telefono.isNotEmpty ? () => _abrirContacto(ctx, telefono) : null,
    );
  }

  Future<void> _abrirContacto(BuildContext ctx, String telefono) async {
    final c = await ContactosRepository().buscarPorTelefono(telefono);
    if (c == null || !ctx.mounted) return;
    Navigator.push(ctx, MaterialPageRoute(
      builder: (_) => ContactoDetalleScreen(contacto: c),
    ));
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom sheets para filtros de stats
// ─────────────────────────────────────────────────────────────
class _ListaReportesSheet extends StatelessWidget {
  final List<dynamic> reportes;
  final String titulo;
  const _ListaReportesSheet({required this.reportes, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Column(
        children: [
          _handle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const Divider(),
          Expanded(
            child: reportes.isEmpty
                ? const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: reportes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final r = reportes[i] as Map;
                      final contacto = r['contacto_nombre']?.toString() ?? '—';
                      final telefono = r['contacto_telefono']?.toString() ?? '';
                      final motivo   = r['motivo']?.toString() ?? '';
                      final fecha    = (r['fecha_reporte']?.toString() ?? '').split('T').first;
                      return ListTile(
                        dense: true,
                        title: Text(contacto, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('📱 $telefono  •  $motivo', style: const TextStyle(fontSize: 11)),
                        trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        onTap: telefono.isNotEmpty ? () async {
                          final c = await ContactosRepository().buscarPorTelefono(telefono);
                          if (c == null || !ctx.mounted) return;
                          Navigator.push(ctx, MaterialPageRoute(
                            builder: (_) => ContactoDetalleScreen(contacto: c),
                          ));
                        } : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ListaAvalesSheet extends StatelessWidget {
  final List<dynamic> avales;
  final String titulo;
  const _ListaAvalesSheet({required this.avales, required this.titulo});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, ctrl) => Column(
        children: [
          _handle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          const Divider(),
          Expanded(
            child: avales.isEmpty
                ? const Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    controller: ctrl,
                    itemCount: avales.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final a = avales[i] as Map;
                      final contacto = a['contacto_nombre']?.toString() ?? '—';
                      final telefono = a['contacto_telefono']?.toString() ?? '';
                      final fecha    = (a['fecha']?.toString() ?? '').split('T').first;
                      return ListTile(
                        dense: true,
                        title: Text(contacto, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('📱 $telefono', style: const TextStyle(fontSize: 11)),
                        trailing: Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        onTap: telefono.isNotEmpty ? () async {
                          final c = await ContactosRepository().buscarPorTelefono(telefono);
                          if (c == null || !ctx.mounted) return;
                          Navigator.push(ctx, MaterialPageRoute(
                            builder: (_) => ContactoDetalleScreen(contacto: c),
                          ));
                        } : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _handle() => Container(
  margin: const EdgeInsets.symmetric(vertical: 12),
  width: 40, height: 4,
  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
);

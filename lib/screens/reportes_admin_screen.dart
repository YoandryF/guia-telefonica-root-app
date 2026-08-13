import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import '../services/telegram_evidence_service.dart';

class ReportesAdminScreen extends StatefulWidget {
  const ReportesAdminScreen({super.key});
  @override
  State<ReportesAdminScreen> createState() => _ReportesAdminScreenState();
}

class _ReportesAdminScreenState extends State<ReportesAdminScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _agrupados = [];
  bool _cargando = true;
  String _orden = 'prioridad'; // prioridad, mas_reportes, recientes
  String _filtro = 'pendiente'; // pendiente, revisado, resuelto, todos

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final response = await _supabase.getReportesAgrupados(filtro: _filtro, orden: _orden);
      setState(() { _agrupados = response; _cargando = false; });
    } catch (e) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.report_problem, color: Colors.orange, size: 20),
          SizedBox(width: 8),
          Text('Reportes'),
        ]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar',
            onSelected: (v) { setState(() => _orden = v); _cargar(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'prioridad', child: Text('🎯 Prioridad (evidencia + volumen)')),
              const PopupMenuItem(value: 'mas_reportes', child: Text('📊 Más reportados')),
              const PopupMenuItem(value: 'recientes', child: Text('🕐 Más recientes')),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            onSelected: (v) { setState(() => _filtro = v); _cargar(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pendiente', child: Text('🟡 Pendientes')),
              const PopupMenuItem(value: 'revisado', child: Text('🔴 Aprobados')),
              const PopupMenuItem(value: 'resuelto', child: Text('✅ Desestimados')),
              const PopupMenuItem(value: 'todos', child: Text('📋 Todos')),
            ],
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _agrupados.isEmpty
              ? const Center(child: Text('No hay reportes'))
              : Column(
                  children: [
                    // Filtro activo
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          Chip(
                            label: Text(_filtroLabel(), style: const TextStyle(fontSize: 11)),
                            backgroundColor: _filtroColor().withOpacity(0.1),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          Text('${_agrupados.length} contactos', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          itemCount: _agrupados.length,
                          itemBuilder: (ctx, i) {
                            final item = _agrupados[i];
                            final aprobados = (item['aprobados'] as num?)?.toInt() ?? 0;
                            final pendientes = (item['pendientes'] as num?)?.toInt() ?? 0;
                            final total = (item['total_reportes'] as num?)?.toInt() ?? 0;
                            final tieneEvidencia = (item['tiene_evidencia'] as bool?) ?? false;
                            final marcado = aprobados > 0;

                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: Stack(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: marcado ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                                      child: Icon(marcado ? Icons.dangerous : Icons.warning_amber,
                                          color: marcado ? Colors.red : Colors.orange, size: 20),
                                    ),
                                    if (tieneEvidencia)
                                      Positioned(
                                        right: 0, bottom: 0,
                                        child: Container(
                                          width: 14, height: 14,
                                          decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1)),
                                          child: const Icon(Icons.attach_file, size: 8, color: Colors.white),
                                        ),
                                      ),
                                  ],
                                ),
                                title: Text('${item['nombre']} ${item['apellido']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('📱 ${item['telefono']}'),
                                    Text('⚠️ $total reportes ($aprobados aprobados, $pendientes pendientes)',
                                        style: const TextStyle(fontSize: 12)),
                                    Text(marcado ? '🔴 Marcado' : '🟡 Sin marcar',
                                        style: TextStyle(fontSize: 11, color: marcado ? Colors.red : Colors.orange)),
                                  ],
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                isThreeLine: true,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => _ReportesContactoScreen(
                                    contactoId: item['contact_id'],
                                    nombre: '${item['nombre']} ${item['apellido']}',
                                  )),
                                ).then((_) => _cargar()),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  String _filtroLabel() {
    switch (_filtro) {
      case 'pendiente': return '🟡 Pendientes';
      case 'revisado': return '🔴 Aprobados';
      case 'resuelto': return '✅ Desestimados';
      default: return '📋 Todos';
    }
  }

  Color _filtroColor() {
    switch (_filtro) {
      case 'pendiente': return Colors.orange;
      case 'revisado': return Colors.red;
      case 'resuelto': return Colors.green;
      default: return Colors.grey;
    }
  }
}

// ============================================
// Pantalla de reportes individuales de un contacto
// ============================================
class _ReportesContactoScreen extends StatefulWidget {
  final String contactoId;
  final String nombre;
  const _ReportesContactoScreen({required this.contactoId, required this.nombre});
  @override
  State<_ReportesContactoScreen> createState() => _ReportesContactoScreenState();
}

class _ReportesContactoScreenState extends State<_ReportesContactoScreen> {
  final _supabase = SupabaseService();
  List<Map<String, dynamic>> _reportes = [];
  Set<String> _seleccionados = {};
  bool _cargando = true;
  bool _modoSeleccion = false;

  // Filtros avanzados
  String? _filtroMotivo;
  String? _filtroEstado;
  bool _soloConEvidencia = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final todos = await _supabase.getReportesDeContacto(
      widget.contactoId,
      filtroMotivo: _filtroMotivo,
      filtroEstado: _filtroEstado,
      soloConEvidencia: _soloConEvidencia,
    );
    setState(() { _reportes = todos; _cargando = false; _seleccionados.clear(); });
  }

  Future<bool> _confirmar(String titulo, String mensaje, {bool destructiva = false}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructiva ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<String?> _pedirNota(String accion) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$accion — Nota (opcional)'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Ej: Verificado, el número sí existe',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          autofocus: false,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Sin nota')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  Future<void> _aprobar(String id) async {
    final nota = await _pedirNota('✅ Aprobar');
    if (nota == null) return;
    await _supabase.aprobarReporte(id, notaAdmin: nota);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Aprobado')));
    _cargar();
  }

  Future<void> _desestimar(String id) async {
    final nota = await _pedirNota('✅ Desestimar');
    if (nota == null) return;
    await _supabase.desestimarReporte(id, notaAdmin: nota);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Desestimado')));
    _cargar();
  }

  Future<void> _eliminar(String id) async {
    if (!await _confirmar('🗑️ ¿Eliminar?', 'Se borra permanentemente.', destructiva: true)) return;
    await _supabase.eliminarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Eliminado')));
    _cargar();
  }

  Future<void> _reactivar(String id) async {
    if (!await _confirmar('♻️ ¿Reactivar?', 'Vuelve a pendiente.')) return;
    await _supabase.reactivarReporte(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('♻️ Reactivado')));
    _cargar();
  }

  Future<void> _aprobarBulk() async {
    if (_seleccionados.isEmpty) return;
    if (!await _confirmar('✅ Aprobar ${_seleccionados.length} reportes', '¿Aprobar todos los seleccionados?')) return;
    await _supabase.aprobarReportesBulk(_seleccionados.toList());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${_seleccionados.length} aprobados')));
    setState(() => _modoSeleccion = false);
    _cargar();
  }

  Future<void> _desestimarBulk() async {
    if (_seleccionados.isEmpty) return;
    if (!await _confirmar('✅ Desestimar ${_seleccionados.length} reportes', '¿Desestimar todos los seleccionados?', destructiva: true)) return;
    await _supabase.desestimarReportesBulk(_seleccionados.toList());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ ${_seleccionados.length} desestimados')));
    setState(() => _modoSeleccion = false);
    _cargar();
  }

  void _mostrarFiltrosAvanzados() {
    String? tempMotivo = _filtroMotivo;
    String? tempEstado = _filtroEstado;
    bool tempEvidencia = _soloConEvidencia;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filtros avanzados', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),

              const Text('Motivo:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Wrap(
                spacing: 8,
                children: [
                  _filtroChip('Todos', null, tempMotivo, (v) => setS(() => tempMotivo = v)),
                  _filtroChip('Spam', 'spam', tempMotivo, (v) => setS(() => tempMotivo = v)),
                  _filtroChip('No existe', 'no_existe', tempMotivo, (v) => setS(() => tempMotivo = v)),
                  _filtroChip('Incorrecto', 'numero_incorrecto', tempMotivo, (v) => setS(() => tempMotivo = v)),
                  _filtroChip('Duplicado', 'duplicado', tempMotivo, (v) => setS(() => tempMotivo = v)),
                  _filtroChip('Otro', 'otro', tempMotivo, (v) => setS(() => tempMotivo = v)),
                ],
              ),
              const SizedBox(height: 12),

              const Text('Estado:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Wrap(
                spacing: 8,
                children: [
                  _filtroChip('Todos', null, tempEstado, (v) => setS(() => tempEstado = v)),
                  _filtroChip('Pendiente', 'pendiente', tempEstado, (v) => setS(() => tempEstado = v)),
                  _filtroChip('Aprobado', 'revisado', tempEstado, (v) => setS(() => tempEstado = v)),
                  _filtroChip('Desestimado', 'resuelto', tempEstado, (v) => setS(() => tempEstado = v)),
                ],
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                title: const Text('Solo con evidencia', style: TextStyle(fontSize: 13)),
                value: tempEvidencia,
                onChanged: (v) => setS(() => tempEvidencia = v),
                dense: true,
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _filtroMotivo = tempMotivo;
                      _filtroEstado = tempEstado;
                      _soloConEvidencia = tempEvidencia;
                    });
                    Navigator.pop(ctx);
                    _cargar();
                  },
                  child: const Text('APLICAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtroChip(String label, String? value, String? current, void Function(String?) onTap) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Chip(
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.white : null)),
        backgroundColor: selected ? Colors.blue : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _abrirEvidencia(dynamic msgId, String? fileId) async {
    if (fileId != null && fileId.toString().isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('📎 Evidencia'),
                automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
              ),
              FutureBuilder<String?>(
                future: TelegramEvidenceService().getEvidenciaUrl(fileId.toString()),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
                  }
                  if (snapshot.data == null) {
                    return const SizedBox(height: 200, child: Center(child: Text('❌ No se pudo cargar')));
                  }
                  return InteractiveViewer(
                    child: Image.network(
                      snapshot.data!,
                      fit: BoxFit.contain,
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return SizedBox(height: 300, child: Center(child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                        )));
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    } else if (msgId != null) {
      final chatId = TelegramEvidenceConfig.evidenceGroupId;
      if (chatId.isNotEmpty) {
        final uri = Uri.parse('https://t.me/c/${chatId.replaceFirst('-100', '')}/$msgId');
        try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
      }
    }
  }

  Future<void> _mostrarStatsReportador(String identificador) async {
    final stats = await _supabase.getStatsReportador(identificador);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📊 Historial del reportador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statRow('Total reportes', '${stats['total']}'),
            _statRow('Aprobados', '${stats['aprobados']}', color: Colors.orange),
            _statRow('Desestimados', '${stats['desestimados']}', color: Colors.green),
            _statRow('Pendientes', '${stats['pendientes']}', color: Colors.grey),
            const Divider(),
            _statRow('Tasa aprobación', '${stats['tasa_aprobacion']}%',
                color: (stats['tasa_aprobacion'] as num) >= 70 ? Colors.orange : Colors.green),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  int get _filtrosActivos => (_filtroMotivo != null ? 1 : 0) + (_filtroEstado != null ? 1 : 0) + (_soloConEvidencia ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.nombre, overflow: TextOverflow.ellipsis),
        actions: [
          if (_filtrosActivos > 0)
            Badge(
              label: Text('$_filtrosActivos'),
              child: IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _mostrarFiltrosAvanzados,
              ),
            )
          else
            IconButton(icon: const Icon(Icons.filter_list), onPressed: _mostrarFiltrosAvanzados),
          IconButton(
            icon: Icon(_modoSeleccion ? Icons.close : Icons.checklist),
            onPressed: () => setState(() {
              _modoSeleccion = !_modoSeleccion;
              _seleccionados.clear();
            }),
            tooltip: _modoSeleccion ? 'Cancelar selección' : 'Selección múltiple',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _reportes.isEmpty
              ? const Center(child: Text('No hay reportes'))
              : ListView.builder(
                  itemCount: _reportes.length,
                  itemBuilder: (ctx, i) {
                    final r = _reportes[i];
                    final estado = r['estado'] ?? '';
                    final estadoIcon = estado == 'revisado' ? '🔴' : estado == 'resuelto' ? '✅' : '🟡';
                    final reportadorId = r['reportado_por'] as String?;

                    // Swipe solo en pendientes
                    Widget card = Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (_modoSeleccion)
                                  Checkbox(
                                    value: _seleccionados.contains(r['id']),
                                    onChanged: (_) => setState(() {
                                      if (_seleccionados.contains(r['id'])) _seleccionados.remove(r['id']);
                                      else _seleccionados.add(r['id']);
                                    }),
                                  ),
                                Expanded(
                                  child: Text('$estadoIcon ${_motivoLabel(r['motivo'] ?? '')}',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                if (r['evidencia_msg_id'] != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text('📎', style: TextStyle(fontSize: 12)),
                                  ),
                                const SizedBox(width: 8),
                                Text(_formatFecha(r['fecha_reporte']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            if (r['descripcion'] != null && r['descripcion'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('💬 ${r['descripcion']}', style: const TextStyle(fontSize: 12)),
                              ),
                            if (r['nota_admin'] != null && r['nota_admin'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('📝 Admin: ${r['nota_admin']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.amber)),
                                ),
                              ),
                            if (r['evidencia_msg_id'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: InkWell(
                                  onTap: () => _abrirEvidencia(r['evidencia_msg_id'], r['evidencia_file_id']),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.image, size: 14, color: Colors.blue),
                                      SizedBox(width: 4),
                                      Text('Ver evidencia', style: TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ),
                            if (reportadorId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: InkWell(
                                  onTap: () => _mostrarStatsReportador(reportadorId),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(reportadorId.length > 20 ? '@${reportadorId.substring(0, 16)}…' : reportadorId,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                      const SizedBox(width: 4),
                                      const Text('(ver historial)', style: TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ),
                            if (!_modoSeleccion) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (estado == 'pendiente') ...[
                                    _actionBtn(Icons.warning_amber, 'Aprobar', Colors.orange, () => _aprobar(r['id'])),
                                    _actionBtn(Icons.check, 'Desestimar', Colors.green, () => _desestimar(r['id'])),
                                  ],
                                  if (estado == 'revisado' || estado == 'resuelto')
                                    _actionBtn(Icons.undo, 'Reactivar', Colors.orange, () => _reactivar(r['id'])),
                                  _actionBtn(Icons.delete, 'Eliminar', Colors.red, () => _eliminar(r['id'])),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );

                    // Swipe solo en pendientes y fuera de modo selección
                    if (estado == 'pendiente' && !_modoSeleccion) {
                      card = Dismissible(
                        key: Key(r['id']),
                        confirmDismiss: (dir) async {
                          if (dir == DismissDirection.startToEnd) {
                            final nota = await _pedirNota('⚠️ Aprobar');
                            if (nota == null) return false;
                            await _supabase.aprobarReporte(r['id'], notaAdmin: nota);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Aprobado')));
                            return true;
                          } else {
                            final nota = await _pedirNota('✅ Desestimar');
                            if (nota == null) return false;
                            await _supabase.desestimarReporte(r['id'], notaAdmin: nota);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Desestimado')));
                            return true;
                          }
                        },
                        onDismissed: (_) => _cargar(),
                        background: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 20),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Icon(Icons.warning_amber, color: Colors.white), Text('Aprobar', style: TextStyle(color: Colors.white, fontSize: 11))],
                          ),
                        ),
                        secondaryBackground: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Icon(Icons.check, color: Colors.white), Text('Desestimar', style: TextStyle(color: Colors.white, fontSize: 11))],
                          ),
                        ),
                        child: card,
                      );
                    }

                    return card;
                  },
                ),
      bottomNavigationBar: _modoSeleccion && _seleccionados.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text('${_seleccionados.length} seleccionados', style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _desestimarBulk,
                      icon: const Icon(Icons.check, size: 16, color: Colors.green),
                      label: const Text('Desestimar', style: TextStyle(color: Colors.green)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _aprobarBulk,
                      icon: const Icon(Icons.warning_amber, size: 16),
                      label: const Text('Aprobar'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
    );
  }

  String _motivoLabel(String motivo) {
    switch (motivo) {
      case 'numero_incorrecto': return '📞 Número incorrecto';
      case 'no_existe': return '❌ No existe';
      case 'spam': return '📢 Spam';
      case 'duplicado': return '🔄 Duplicado';
      default: return '📋 Otro';
    }
  }

  String _formatFecha(dynamic fecha) {
    if (fecha == null) return '';
    try {
      final dt = DateTime.parse(fecha.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}min';
      if (diff.inHours < 24) return 'hace ${diff.inHours}h';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }
}

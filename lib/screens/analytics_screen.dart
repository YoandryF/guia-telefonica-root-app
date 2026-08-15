import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';
import '../screens/contacto_detalle_screen.dart';
import '../services/supabase_service.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = SupabaseService();
  Map<String, dynamic> _data = {};
  bool _cargando = true;
  late TabController _tabs;

  final _tabLabels = [
    '📣 Reportadores',
    '🔴 Reportados',
    '❌ Fallas',
    '👍 Avaladores',
    '⭐ Trust',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await _supabase.getAnalyticsAdmin();
    setState(() {
      _data = data;
      _cargando = false;
    });
  }

  List<dynamic> _lista(String key) {
    final v = _data[key];
    if (v == null) return [];
    if (v is List) return v;
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
            tooltip: 'Actualizar',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _TabReportadores(_lista('top_reportadores')),
                  _TabReportados(_lista('top_reportados')),
                  _TabFallas(_lista('top_fallas')),
                  _TabAvaladores(_lista('top_avaladores')),
                  _TabTrust(
                    mejores: _lista('top_trust'),
                    peores: _lista('peor_trust'),
                  ),
                ],
              ),
            ),
    );
  }
}

// ============================================================
// TAB 1 — Top reportadores
// ============================================================
class _TabReportadores extends StatefulWidget {
  final List<dynamic> items;
  const _TabReportadores(this.items);
  @override
  State<_TabReportadores> createState() => _TabReportadoresState();
}

class _TabReportadoresState extends State<_TabReportadores> {
  String _query = '';

  List<dynamic> get _filtrados => widget.items
      .where((r) => (r['identificador'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
      .toList();

  int get _maxTotal => widget.items.isEmpty ? 1 :
      (widget.items.map((r) => (r['total'] as num?) ?? 0).reduce((a, b) => a > b ? a : b)).toInt();

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const _Vacio('Sin datos de reportadores');
    return Column(
      children: [
        _Buscador(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _filtrados.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = _filtrados[i] as Map;
              final id = item['identificador']?.toString() ?? '—';
              final total = (item['total'] as num?)?.toInt() ?? 0;
              final aprobados = (item['aprobados'] as num?)?.toInt() ?? 0;
              final pendientes = (item['pendientes'] as num?)?.toInt() ?? 0;
              final pct = total > 0 ? aprobados / total : 0.0;
              return ListTile(
                leading: _Puesto(_filtrados.indexOf(item) + 1),
                title: Text(_truncar(id),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _BarraProgreso(
                      valor: total / _maxTotal,
                      color: Colors.orange,
                      label: '$total reportes',
                    ),
                    const SizedBox(height: 4),
                    Text('✅ $aprobados aprobados  ⏳ $pendientes pendientes',
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Badge('$total', Colors.orange),
                    Text('${(pct * 100).toStringAsFixed(0)}% apr.',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                onTap: () => _verReportes(ctx, id),
              );
            },
          ),
        ),
      ],
    );
  }

  void _verReportes(BuildContext ctx, String identificador) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _ReportesUsuarioSheet(identificador: identificador),
    );
  }
}

// ============================================================
// TAB 2 — Top números más reportados
// ============================================================
class _TabReportados extends StatefulWidget {
  final List<dynamic> items;
  const _TabReportados(this.items);
  @override
  State<_TabReportados> createState() => _TabReportadosState();
}

class _TabReportadosState extends State<_TabReportados> {
  String _query = '';

  List<dynamic> get _filtrados => widget.items
      .where((r) =>
          (r['nombre'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()) ||
          (r['telefono'] ?? '').toString().contains(_query))
      .toList();

  int get _maxScore => widget.items.isEmpty ? 1 :
      (widget.items.map((r) => (r['score_riesgo'] as num?) ?? 0).reduce((a, b) => a > b ? a : b)).toInt();

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const _Vacio('Sin contactos reportados');
    return Column(
      children: [
        _Buscador(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _filtrados.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = _filtrados[i] as Map;
              final nombre = item['nombre']?.toString() ?? '—';
              final telefono = item['telefono']?.toString() ?? '—';
              final score = (item['score_riesgo'] as num?)?.toDouble() ?? 0.0;
              final verificado = item['verificado'] == true;
              final total = (item['total_reportes'] as num?)?.toInt() ?? 0;
              return ListTile(
                leading: _Puesto(i + 1),
                title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📱 $telefono  ${verificado ? '🔴 Verificado' : '🟡 Reportado'}',
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 4),
                    _BarraProgreso(
                      valor: _maxScore > 0 ? score / _maxScore : 0,
                      color: score > 60 ? Colors.red : score > 30 ? Colors.orange : Colors.yellow[700]!,
                      label: 'Score ${score.toStringAsFixed(0)}',
                    ),
                  ],
                ),
                trailing: _Badge('$total rep.', Colors.red),
                onTap: () => _abrirContacto(ctx, telefono),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _abrirContacto(BuildContext ctx, String telefono) async {
    final client = Supabase.instance.client;
    try {
      final data = await client
          .from('contactos')
          .select('*, categorias(nombre, icono)')
          .eq('telefono', telefono)
          .maybeSingle();
      if (data == null || !ctx.mounted) return;
      Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => ContactoDetalleScreen(contacto: Contacto.fromJson(data)),
      ));
    } catch (_) {}
  }
}

// ============================================================
// TAB 3 — Top usuarios con más fallas
// ============================================================
class _TabFallas extends StatefulWidget {
  final List<dynamic> items;
  const _TabFallas(this.items);
  @override
  State<_TabFallas> createState() => _TabFallasState();
}

class _TabFallasState extends State<_TabFallas> {
  String _query = '';

  List<dynamic> get _filtrados => widget.items
      .where((r) => (r['identificador'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
      .toList();

  int get _maxFallas => widget.items.isEmpty ? 1 :
      (widget.items.map((r) => (r['desestimados'] as num?) ?? 0).reduce((a, b) => a > b ? a : b)).toInt();

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const _Vacio('Sin usuarios con fallas');
    return Column(
      children: [
        _Buscador(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _filtrados.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = _filtrados[i] as Map;
              final id = item['identificador']?.toString() ?? '—';
              final desestimados = (item['desestimados'] as num?)?.toInt() ?? 0;
              final aprobados = (item['aprobados'] as num?)?.toInt() ?? 0;
              final pct = item['pct_fallas']?.toString() ?? '0';
              final pctVal = double.tryParse(pct) ?? 0;
              return ListTile(
                leading: _Puesto(i + 1),
                title: Text(_truncar(id),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _BarraProgreso(
                      valor: desestimados / _maxFallas,
                      color: pctVal > 70 ? Colors.red : Colors.deepOrange,
                      label: '$desestimados desestimados',
                    ),
                    const SizedBox(height: 4),
                    Text('✅ $aprobados aprobados', style: const TextStyle(fontSize: 11)),
                  ],
                ),
                trailing: _Badge('$pct%', pctVal > 70 ? Colors.red : Colors.deepOrange),
                onTap: () => _verReportes(ctx, id),
              );
            },
          ),
        ),
      ],
    );
  }

  void _verReportes(BuildContext ctx, String identificador) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _ReportesUsuarioSheet(identificador: identificador),
    );
  }
}

// ============================================================
// TAB 4 — Top avaladores
// ============================================================
class _TabAvaladores extends StatefulWidget {
  final List<dynamic> items;
  const _TabAvaladores(this.items);
  @override
  State<_TabAvaladores> createState() => _TabAvaldoresState();
}

class _TabAvaldoresState extends State<_TabAvaladores> {
  String _query = '';

  List<dynamic> get _filtrados => widget.items
      .where((r) => (r['identificador'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
      .toList();

  int get _maxTotal => widget.items.isEmpty ? 1 :
      (widget.items.map((r) => (r['total_avales'] as num?) ?? 0).reduce((a, b) => a > b ? a : b)).toInt();

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const _Vacio('Sin datos de avales');
    return Column(
      children: [
        _Buscador(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _filtrados.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final item = _filtrados[i] as Map;
              final id = item['identificador']?.toString() ?? '—';
              final total = (item['total_avales'] as num?)?.toInt() ?? 0;
              final aprobados = (item['aprobados'] as num?)?.toInt() ?? 0;
              final pendientes = (item['pendientes'] as num?)?.toInt() ?? 0;
              final rechazados = (item['rechazados'] as num?)?.toInt() ?? 0;
              return ListTile(
                leading: _Puesto(i + 1),
                title: Text(_truncar(id),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    _BarraProgreso(
                      valor: total / _maxTotal,
                      color: Colors.green,
                      label: '$total avales',
                    ),
                    const SizedBox(height: 4),
                    Text('✅ $aprobados  ⏳ $pendientes  ❌ $rechazados',
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
                trailing: _Badge('$total', Colors.green),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TAB 5 — Trust score (mejor y peor)
// ============================================================
class _TabTrust extends StatefulWidget {
  final List<dynamic> mejores;
  final List<dynamic> peores;
  const _TabTrust({required this.mejores, required this.peores});
  @override
  State<_TabTrust> createState() => _TabTrustState();
}

class _TabTrustState extends State<_TabTrust> {
  String _query = '';

  List<dynamic> _filtrar(List<dynamic> lista) => lista
      .where((r) => (r['identificador'] ?? '').toString().toLowerCase().contains(_query.toLowerCase()))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Buscador(onChanged: (v) => setState(() => _query = v)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              _SeccionTitulo('⭐ Mejor trust score'),
              if (_filtrar(widget.mejores).isEmpty)
                const _Vacio('Sin datos (mín. 3 reportes)')
              else
                ..._filtrar(widget.mejores).asMap().entries.map((e) =>
                    _TrustTile(item: e.value, puesto: e.key + 1, esMejor: true,
                        onTap: () => _verReportes(context, e.value['identificador']?.toString() ?? ''))),
              const SizedBox(height: 16),
              _SeccionTitulo('💀 Peor trust score'),
              if (_filtrar(widget.peores).isEmpty)
                const _Vacio('Sin datos (mín. 3 reportes)')
              else
                ..._filtrar(widget.peores).asMap().entries.map((e) =>
                    _TrustTile(item: e.value, puesto: e.key + 1, esMejor: false,
                        onTap: () => _verReportes(context, e.value['identificador']?.toString() ?? ''))),
            ],
          ),
        ),
      ],
    );
  }

  void _verReportes(BuildContext ctx, String identificador) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _ReportesUsuarioSheet(identificador: identificador),
    );
  }
}

class _TrustTile extends StatelessWidget {
  final Map item;
  final int puesto;
  final bool esMejor;
  final VoidCallback onTap;
  const _TrustTile({required this.item, required this.puesto, required this.esMejor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = item['identificador']?.toString() ?? '—';
    final trust = (item['trust_pct'] as num?)?.toDouble() ?? 0;
    final total = (item['total'] as num?)?.toInt() ?? 0;
    final color = esMejor ? Colors.green : Colors.red;
    return ListTile(
      dense: true,
      leading: _Puesto(puesto),
      title: Text(_truncar(id), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          _BarraProgreso(valor: trust / 100, color: color, label: '$total reportes totales'),
        ],
      ),
      trailing: _Badge('${trust.toStringAsFixed(0)}%', color),
      onTap: onTap,
    );
  }
}

// ============================================================
// Bottom sheet — reportes de un usuario
// ============================================================
class _ReportesUsuarioSheet extends StatefulWidget {
  final String identificador;
  const _ReportesUsuarioSheet({required this.identificador});

  @override
  State<_ReportesUsuarioSheet> createState() => _ReportesUsuarioSheetState();
}

class _ReportesUsuarioSheetState extends State<_ReportesUsuarioSheet> {
  List<Map<String, dynamic>> _reportes = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await Supabase.instance.client
          .from('reportes')
          .select('id, motivo, estado, fecha_reporte, nota_admin, contactos(nombre, apellido, telefono)')
          .eq('reportado_por', widget.identificador)
          .order('fecha_reporte', ascending: false)
          .limit(50);
      setState(() {
        _reportes = List<Map<String, dynamic>>.from(r);
        _cargando = false;
      });
    } catch (_) {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.person, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reportes de ${_truncar(widget.identificador)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_cargando)
                  Text('${_reportes.length}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _reportes.isEmpty
                    ? const _Vacio('Sin reportes')
                    : ListView.separated(
                        controller: controller,
                        itemCount: _reportes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _reportes[i];
                          final contacto = r['contactos'] as Map?;
                          final nombre = contacto != null
                              ? '${contacto['nombre']} ${contacto['apellido']}'
                              : '—';
                          final telefono = contacto?['telefono']?.toString() ?? '';
                          final estado = r['estado']?.toString() ?? '';
                          final fecha = (r['fecha_reporte']?.toString() ?? '').split('T').first;
                          final nota = r['nota_admin']?.toString();

                          final estadoColor = estado == 'revisado'
                              ? Colors.green
                              : estado == 'resuelto'
                                  ? Colors.red
                                  : Colors.orange;
                          final estadoLabel = estado == 'revisado'
                              ? '✅ Aprobado'
                              : estado == 'resuelto'
                                  ? '❌ Desestimado'
                                  : '⏳ Pendiente';

                          return ListTile(
                            dense: true,
                            title: Text(nombre, style: const TextStyle(fontSize: 13)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📱 $telefono  •  ${r['motivo'] ?? ''}',
                                    style: const TextStyle(fontSize: 11)),
                                if (nota != null && nota.isNotEmpty)
                                  Text('📝 $nota',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(estadoLabel,
                                    style: TextStyle(fontSize: 11, color: estadoColor)),
                                Text(fecha,
                                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Widgets auxiliares
// ============================================================
class _Buscador extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _Buscador({required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Buscar...',
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
      ),
    ),
  );
}

class _BarraProgreso extends StatelessWidget {
  final double valor;
  final Color color;
  final String label;
  const _BarraProgreso({required this.valor, required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: valor.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 10, color: color)),
    ],
  );
}

class _Puesto extends StatelessWidget {
  final int numero;
  const _Puesto(this.numero);

  @override
  Widget build(BuildContext context) {
    final colores = [Colors.amber, Colors.grey, Colors.brown];
    final color = numero <= 3 ? colores[numero - 1] : Colors.blueGrey;
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withOpacity(0.2),
      child: Text('$numero',
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
    );
  }
}

class _Badge extends StatelessWidget {
  final String texto;
  final Color color;
  const _Badge(this.texto, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(texto,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

class _SeccionTitulo extends StatelessWidget {
  final String titulo;
  const _SeccionTitulo(this.titulo);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Vacio extends StatelessWidget {
  final String mensaje;
  const _Vacio(this.mensaje);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(mensaje, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String _truncar(String s) =>
    s.length > 20 ? '${s.substring(0, 8)}…${s.substring(s.length - 6)}' : s;

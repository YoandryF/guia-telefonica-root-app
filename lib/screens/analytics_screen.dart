import 'package:flutter/material.dart';
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
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
    );
  }
}

// ============================================================
// TAB 1 — Top reportadores
// ============================================================
class _TabReportadores extends StatelessWidget {
  final List<dynamic> items;
  const _TabReportadores(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _Vacio('Sin datos de reportadores');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i] as Map;
        final id = _truncar(item['identificador']?.toString() ?? '—');
        final total = item['total'] ?? 0;
        final aprobados = item['aprobados'] ?? 0;
        final pendientes = item['pendientes'] ?? 0;
        return ListTile(
          leading: _Puesto(i + 1),
          title: Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          subtitle: Text('✅ $aprobados aprobados  ⏳ $pendientes pendientes'),
          trailing: _Badge('$total', Colors.orange),
        );
      },
    );
  }
}

// ============================================================
// TAB 2 — Top números más reportados
// ============================================================
class _TabReportados extends StatelessWidget {
  final List<dynamic> items;
  const _TabReportados(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _Vacio('Sin contactos reportados');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i] as Map;
        final nombre = item['nombre']?.toString() ?? '—';
        final telefono = item['telefono']?.toString() ?? '—';
        final score = (item['score_riesgo'] as num?)?.toStringAsFixed(0) ?? '0';
        final verificado = item['verificado'] == true;
        final total = item['total_reportes'] ?? 0;
        return ListTile(
          leading: _Puesto(i + 1),
          title: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('📱 $telefono  ${verificado ? '🔴 Verificado' : '🟡 Reportado'}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge('$total rep.', Colors.red),
              const SizedBox(height: 2),
              Text('Score $score', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================
// TAB 3 — Top usuarios con más fallas
// ============================================================
class _TabFallas extends StatelessWidget {
  final List<dynamic> items;
  const _TabFallas(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _Vacio('Sin usuarios con fallas');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i] as Map;
        final id = _truncar(item['identificador']?.toString() ?? '—');
        final desestimados = item['desestimados'] ?? 0;
        final aprobados = item['aprobados'] ?? 0;
        final pct = item['pct_fallas']?.toString() ?? '0';
        return ListTile(
          leading: _Puesto(i + 1),
          title: Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          subtitle: Text('✅ $aprobados aprobados  ❌ $desestimados desestimados'),
          trailing: _Badge('$pct%', Colors.deepOrange),
        );
      },
    );
  }
}

// ============================================================
// TAB 4 — Top avaladores
// ============================================================
class _TabAvaladores extends StatelessWidget {
  final List<dynamic> items;
  const _TabAvaladores(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const _Vacio('Sin datos de avales');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i] as Map;
        final id = _truncar(item['identificador']?.toString() ?? '—');
        final total = item['total_avales'] ?? 0;
        final aprobados = item['aprobados'] ?? 0;
        final pendientes = item['pendientes'] ?? 0;
        final rechazados = item['rechazados'] ?? 0;
        return ListTile(
          leading: _Puesto(i + 1),
          title: Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          subtitle: Text('✅ $aprobados  ⏳ $pendientes  ❌ $rechazados'),
          trailing: _Badge('$total', Colors.green),
        );
      },
    );
  }
}

// ============================================================
// TAB 5 — Trust score (mejor y peor)
// ============================================================
class _TabTrust extends StatelessWidget {
  final List<dynamic> mejores;
  final List<dynamic> peores;
  const _TabTrust({required this.mejores, required this.peores});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SeccionTitulo('⭐ Mejor trust score'),
        if (mejores.isEmpty)
          const _Vacio('Sin datos suficientes (mín. 3 reportes)')
        else
          ...mejores.asMap().entries.map((e) {
            final item = e.value as Map;
            final id = _truncar(item['identificador']?.toString() ?? '—');
            final trust = item['trust_pct']?.toString() ?? '0';
            final total = item['total'] ?? 0;
            return ListTile(
              dense: true,
              leading: _Puesto(e.key + 1),
              title: Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              subtitle: Text('$total reportes totales'),
              trailing: _Badge('$trust%', Colors.green),
            );
          }),
        const SizedBox(height: 24),
        _SeccionTitulo('💀 Peor trust score'),
        if (peores.isEmpty)
          const _Vacio('Sin datos suficientes (mín. 3 reportes)')
        else
          ...peores.asMap().entries.map((e) {
            final item = e.value as Map;
            final id = _truncar(item['identificador']?.toString() ?? '—');
            final trust = item['trust_pct']?.toString() ?? '0';
            final total = item['total'] ?? 0;
            return ListTile(
              dense: true,
              leading: _Puesto(e.key + 1),
              title: Text(id, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              subtitle: Text('$total reportes totales'),
              trailing: _Badge('$trust%', Colors.red),
            );
          }),
      ],
    );
  }
}

// ============================================================
// Widgets auxiliares
// ============================================================
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
      child: Text('$numero', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
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
        child: Text(texto, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      );
}

class _SeccionTitulo extends StatelessWidget {
  final String titulo;
  const _SeccionTitulo(this.titulo);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Vacio extends StatelessWidget {
  final String mensaje;
  const _Vacio(this.mensaje);

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(mensaje, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}

String _truncar(String s) => s.length > 20 ? '${s.substring(0, 8)}…${s.substring(s.length - 6)}' : s;

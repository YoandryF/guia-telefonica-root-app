import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import 'contacto_detalle_screen.dart';

class ListaNegraScreen extends StatefulWidget {
  const ListaNegraScreen({super.key});
  @override
  State<ListaNegraScreen> createState() => _ListaNegraScreenState();
}

class _ListaNegraScreenState extends State<ListaNegraScreen> {
  final _localDb = LocalDatabaseService();
  List<Contacto> _reportados = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    // Query directa por tiene_reportes=1 — NO cargar 70k en memoria
    final db = await _localDb.database;
    final maps = await db.query(
      'contactos_aprobados',
      where: 'tiene_reportes = 1',
      orderBy: 'nombre ASC',
    );
    setState(() {
      _reportados = maps.map((m) => Contacto.fromJson(m)).toList();
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('⚠️ Lista Negra')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _reportados.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('No hay contactos reportados', style: TextStyle(fontSize: 16)),
                      SizedBox(height: 8),
                      Text('La guía está limpia', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Card(
                        color: Colors.red.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.red),
                              const SizedBox(width: 8),
                              Text('${_reportados.length} contacto(s) de riesgo',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _reportados.length,
                        itemBuilder: (ctx, i) {
                          final c = _reportados[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.red,
                                child: Icon(Icons.warning, color: Colors.white, size: 20),
                              ),
                              title: Text(c.nombreCompleto),
                              subtitle: Text('📱 ${c.telefono}'),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ContactoDetalleScreen(contacto: c))),
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

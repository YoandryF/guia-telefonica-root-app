import 'package:flutter/material.dart';
import '../models/contacto.dart';
import '../services/export_service.dart';
import '../services/supabase_service.dart';

class ExportarScreen extends StatefulWidget {
  const ExportarScreen({super.key});

  @override
  State<ExportarScreen> createState() => _ExportarScreenState();
}

class _ExportarScreenState extends State<ExportarScreen> {
  final _supabase = SupabaseService();
  final _export = ExportService();

  String _formato = 'csv';
  String _filtro = 'aprobado';
  bool _exportando = false;
  List<Contacto>? _contactos;

  Future<void> _exportar() async {
    setState(() => _exportando = true);

    try {
      final contactos = await _supabase.getContactosPorEstado(_filtro, limit: 10000);
      setState(() => _contactos = contactos);

      if (contactos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay contactos para exportar')),
          );
        }
        setState(() => _exportando = false);
        return;
      }

      if (_formato == 'csv') {
        await _export.exportarCSV(contactos);
      } else if (_formato == 'pdf') {
        await _export.exportarPDF(contactos);
      } else {
        await _export.exportarJSON(contactos);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _exportando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Row(children: [Icon(Icons.upload_file, size: 20), SizedBox(width: 8), Text('Exportar')])),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Formato
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Formato', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'csv', label: Text('CSV'), icon: Icon(Icons.table_chart)),
                        ButtonSegment(value: 'json', label: Text('JSON'), icon: Icon(Icons.code)),
                        ButtonSegment(value: 'pdf', label: Text('PDF'), icon: Icon(Icons.picture_as_pdf)),
                      ],
                      selected: {_formato},
                      onSelectionChanged: (s) => setState(() => _formato = s.first),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Filtro
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contactos a exportar', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'aprobado', label: Text('Aprobados')),
                        ButtonSegment(value: 'pendiente', label: Text('Pendientes')),
                        ButtonSegment(value: 'todos', label: Text('Todos')),
                      ],
                      selected: {_filtro},
                      onSelectionChanged: (s) => setState(() => _filtro = s.first),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Botón exportar
            FilledButton.icon(
              onPressed: _exportando ? null : _exportar,
              icon: _exportando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download),
              label: Text(_exportando ? 'Generando...' : 'GENERAR Y COMPARTIR'),
            ),

            if (_contactos != null) ...[
              const SizedBox(height: 16),
              Text(
                '✅ Último export: ${_contactos!.length} contactos (${_formato.toUpperCase()})',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

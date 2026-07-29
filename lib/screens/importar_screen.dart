import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/import_service.dart';

class ImportarScreen extends StatefulWidget {
  const ImportarScreen({super.key});

  @override
  State<ImportarScreen> createState() => _ImportarScreenState();
}

class _ImportarScreenState extends State<ImportarScreen> {
  final _import = ImportService();

  PlatformFile? _archivo;
  List<Map<String, String>>? _preview;
  ImportResult? _resultado;
  bool _importando = false;

  Future<void> _seleccionar() async {
    final file = await _import.seleccionarArchivo();
    if (file == null) return;

    setState(() {
      _archivo = file;
      _resultado = null;
    });

    final preview = await _import.preview(file);
    setState(() => _preview = preview);
  }

  Future<void> _confirmarImportar() async {
    if (_archivo == null) return;

    setState(() => _importando = true);

    final resultado = await _import.importar(_archivo!);

    setState(() {
      _resultado = resultado;
      _importando = false;
    });

    if (mounted && resultado.errorDetalle != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${resultado.errorDetalle}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📥 Importar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seleccionar archivo
            OutlinedButton.icon(
              onPressed: _seleccionar,
              icon: const Icon(Icons.folder_open),
              label: const Text('Seleccionar archivo (CSV o JSON)'),
            ),

            if (_archivo != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('📄 ${_archivo!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('📦 ${(_archivo!.size / 1024).toStringAsFixed(1)} KB'),
                      Text('📊 Preview: ${_preview?.length ?? 0} registros'),
                    ],
                  ),
                ),
              ),
            ],

            // Preview
            if (_preview != null && _preview!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Vista previa (primeros 5):', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _preview!.length,
                  itemBuilder: (ctx, i) {
                    final c = _preview![i];
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text('${c['nombre'] ?? ''} ${c['apellido'] ?? ''}'),
                        subtitle: Text('📱 ${c['telefono'] ?? ''}'),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // Botón importar
              FilledButton.icon(
                onPressed: _importando ? null : _confirmarImportar,
                icon: _importando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_importando ? 'Importando...' : 'CONFIRMAR IMPORTACIÓN'),
              ),

              const SizedBox(height: 8),
              const Text(
                'ℹ️ Los contactos importados quedan pendientes de aprobación.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],

            // Resultado
            if (_resultado != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('✅ Importación completada', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('📊 Procesados: ${_resultado!.procesados}'),
                      Text('✅ Nuevos: ${_resultado!.nuevos}'),
                      Text('⚠️ Duplicados: ${_resultado!.duplicados}'),
                      Text('❌ Errores: ${_resultado!.errores}'),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

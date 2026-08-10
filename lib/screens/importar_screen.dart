import 'dart:io';
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
  int _totalRegistros = 0;
  ImportResult? _resultado;
  bool _importando = false;
  double _progreso = 0;
  String _status = '';
  int _chunkFallido = 0;

  @override
  void initState() {
    super.initState();
    _verificarPendiente();
  }

  Future<void> _verificarPendiente() async {
    final pendiente = await _import.getImportPendiente();
    if (pendiente != null && mounted) {
      setState(() {
        _status = 'Importación interrumpida en chunk ${pendiente['chunk']}. Selecciona el archivo y toca Reintentar.';
        _chunkFallido = pendiente['chunk'] as int;
      });
    }
  }

  Future<void> _seleccionar() async {
    final file = await _import.seleccionarArchivo();
    if (file == null) return;
    final preview = await _import.preview(file);
    final total = await _import.contarRegistros(file);
    setState(() { _archivo = file; _preview = preview; _totalRegistros = total; _resultado = null; });
  }

  Future<void> _iniciarImport({int desdeChunk = 0}) async {
    if (_archivo == null) return;
    setState(() { _importando = true; _resultado = null; _progreso = 0; _status = 'Importando...'; });

    await for (final result in _import.importarStream(_archivo!, desdeChunk: desdeChunk)) {
      if (!mounted) return;
      setState(() {
        _resultado = result;
        _progreso = result.totalChunks > 0 ? result.chunkActual / result.totalChunks : 0;
        _status = result.completado
            ? '✅ Importación completada'
            : result.errorDetalle != null
                ? '⚠️ ${result.errorDetalle}'
                : 'Chunk ${result.chunkActual}/${result.totalChunks}';
        if (!result.completado && result.errorDetalle != null) {
          _chunkFallido = result.chunkActual;
        }
      });
    }

    setState(() => _importando = false);
  }

  Future<void> _cancelarPendiente() async {
    await _import.cancelarImportPendiente();
    setState(() { _chunkFallido = 0; _status = ''; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📥 Importar')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _importando ? null : _seleccionar,
              icon: const Icon(Icons.folder_open),
              label: const Text('Seleccionar archivo (CSV o JSON)'),
            ),

            if (_archivo != null) ...[
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📄 ${_archivo!.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('📦 ${(_archivo!.size / 1024 / 1024).toStringAsFixed(1)} MB'),
                  Text('📊 $_totalRegistros registros'),
                  if (_totalRegistros > 0) Text('📦 ${(_totalRegistros / 100).ceil()} chunks de 100'),
                ],
              ))),
            ],

            if (_preview != null && _preview!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Vista previa:', style: Theme.of(context).textTheme.titleSmall),
              ...(_preview!.map((c) => Card(child: ListTile(
                dense: true,
                title: Text('${c['nombre'] ?? ''} ${c['apellido'] ?? ''}'),
                subtitle: Text('📱 ${c['telefono'] ?? ''}'),
              )))),
            ],

            const SizedBox(height: 16),

            // Barra de progreso
            if (_importando || (_resultado != null && !_resultado!.completado)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _progreso, minHeight: 12),
              ),
              const SizedBox(height: 8),
              Text('${(_progreso * 100).toStringAsFixed(0)}% — $_status', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              if (_resultado != null) ...[
                const SizedBox(height: 4),
                Text('✅ ${_resultado!.nuevos} nuevos | ⚠️ ${_resultado!.duplicados} dup. | ❌ ${_resultado!.errores} err.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ],

            const SizedBox(height: 12),

            // Botones
            if (!_importando && _archivo != null && (_resultado == null || _resultado!.completado))
              FilledButton.icon(
                onPressed: () => _iniciarImport(),
                icon: const Icon(Icons.upload_file),
                label: const Text('IMPORTAR'),
              ),

            if (!_importando && _chunkFallido > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: FilledButton.icon(
                    onPressed: () => _iniciarImport(desdeChunk: _chunkFallido),
                    icon: const Icon(Icons.refresh),
                    label: const Text('REINTENTAR'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  )),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: _cancelarPendiente, child: const Text('Cancelar')),
                ]),
              ),

            // Resultado final
            if (_resultado != null && _resultado!.completado) ...[
              const SizedBox(height: 16),
              Card(color: Colors.green.withOpacity(0.1), child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 40),
                const SizedBox(height: 8),
                const Text('✅ Importación completada', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('📊 Procesados: ${_resultado!.procesados}'),
                Text('✅ Nuevos: ${_resultado!.nuevos}'),
                Text('⚠️ Duplicados: ${_resultado!.duplicados}'),
                Text('❌ Errores: ${_resultado!.errores}'),
              ]))),
            ],

            const SizedBox(height: 8),
            const Text('ℹ️ Los contactos importados quedan pendientes de aprobación.', style: TextStyle(color: Colors.grey, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

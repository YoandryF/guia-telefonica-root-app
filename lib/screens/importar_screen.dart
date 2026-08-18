import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/import_service.dart';
import 'errores_import_screen.dart';

class ImportarScreen extends StatefulWidget {
  const ImportarScreen({super.key});
  @override
  State<ImportarScreen> createState() => _ImportarScreenState();
}

class _ImportarScreenState extends State<ImportarScreen> with WidgetsBindingObserver {
  final _import = ImportService();
  PlatformFile? _archivo;
  List<Map<String, String>>? _preview;
  int _totalRegistros = 0;
  ImportResult? _resultado;
  bool _importando = false;
  double _progreso = 0;
  String _status = '';
  int _chunkFallido = 0;
  DateTime? _inicioImport;
  // Contador actualizable de errores restantes
  int _erroresRestantes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verificarPendiente();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No cancelar import si la app va a background
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

  String _tiempoEstimado(ImportResult r) {
    if (_inicioImport == null || r.chunkActual == 0) return '';
    final elapsed = DateTime.now().difference(_inicioImport!).inSeconds;
    if (elapsed < 3) return '';
    final chunksRestantes = r.totalChunks - r.chunkActual;
    final segsPerChunk = elapsed / r.chunkActual;
    final segsRestantes = (chunksRestantes * segsPerChunk).round();
    if (segsRestantes < 60) return '~${segsRestantes}s restantes';
    final mins = (segsRestantes / 60).ceil();
    return '~${mins}min restantes';
  }

  Future<void> _iniciarImport({int desdeChunk = 0}) async {
    if (_archivo == null) return;
    setState(() {
      _importando = true;
      _resultado = null;
      _progreso = 0;
      _status = 'Iniciando importación...';
      _inicioImport = DateTime.now();
    });

    await for (final result in _import.importarStream(_archivo!, desdeChunk: desdeChunk)) {
      if (!mounted) return;
      final tiempo = _tiempoEstimado(result);
      setState(() {
        _resultado = result;
        _progreso = result.totalChunks > 0 ? result.chunkActual / result.totalChunks : 0;
        if (result.completado) {
          _status = '✅ Importación completada';
          // Inicializar contador de errores restantes
          _erroresRestantes = result.registrosConError.length;
        } else if (result.errorDetalle != null) {
          _status = '⚠️ ${result.errorDetalle}';
          _chunkFallido = result.chunkActual;
        } else {
          _status = 'Chunk ${result.chunkActual}/${result.totalChunks}${tiempo.isNotEmpty ? ' — $tiempo' : ''}';
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
    return PopScope(
      canPop: !_importando,
      onPopInvoked: (didPop) {
        if (!didPop && _importando) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Importación en progreso. Espera a que termine.')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Row(children: [Icon(Icons.download_for_offline, size: 20), SizedBox(width: 8), Text('Importar')])),
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
                    if (_totalRegistros > 0) Text('📦 ${(_totalRegistros / 500).ceil()} chunks de 500'),
                  ],
                ))),
              ],

              if (_preview != null && _preview!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Vista previa:', style: Theme.of(context).textTheme.titleSmall),
                ...(_preview!.map((c) => Card(child: ListTile(
                  dense: true,
                  title: Text('${c['nombre'] ?? ''} ${c['apellido'] ?? ''}'),
                  subtitle: Text('📱 ${c['telefono'] ?? ''}${c['provincia'] != null ? ' | ${c['provincia']}' : ''}'),
                )))),
              ],

              const SizedBox(height: 16),

              // Barra de progreso + stats en tiempo real
              if (_importando || (_resultado != null && !_resultado!.completado)) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: _progreso, minHeight: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_progreso * 100).toStringAsFixed(0)}% — $_status',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                if (_resultado != null) ...[
                  const SizedBox(height: 12),
                  _StatsRow(result: _resultado!),
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
                  const Text('✅ Importación completada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _StatsRow(result: _resultado!, final_: true),
                  if (_inicioImport != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '⏱️ Duración: ${DateTime.now().difference(_inicioImport!).inSeconds}s',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ]))),
                // Lista de errores si hay — navegar a pantalla de edición
                if (_erroresRestantes > 0) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final guardados = await Navigator.push<int>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ErroresImportScreen(
                            errores: List.from(_resultado!.registrosConError),
                          ),
                        ),
                      );
                      if (guardados != null && guardados > 0 && mounted) {
                        setState(() {
                          _erroresRestantes -= guardados;
                          if (_erroresRestantes < 0) _erroresRestantes = 0;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ $guardados contactos adicionales aprobados'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.edit, color: Colors.orange),
                    label: Text(
                      '⚠️ $_erroresRestantes errores — Revisar y corregir',
                      style: const TextStyle(color: Colors.orange),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 8),
              Text(
                _importando
                    ? '⚠️ No salgas de esta pantalla mientras importa.'
                    : 'ℹ️ Contactos sin estado se importan como pendientes. Con estado "aprobado" se importan directamente.',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final ImportResult result;
  final bool final_;

  const _StatsRow({required this.result, this.final_ = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: final_ ? 13 : 11,
      fontWeight: final_ ? FontWeight.w500 : FontWeight.normal,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        _chip('✅ ${result.nuevos}', 'nuevos', Colors.green, style),
        _chip('🔄 ${result.actualizados}', 'actual.', Colors.blue, style),
        _chip('⏭️ ${result.duplicados}', 'ignor.', Colors.orange, style),
        _chip('❌ ${result.errores}', 'errores', Colors.red, style),
        _chip('📊 ${result.procesados}', 'total', Colors.grey, style),
      ],
    );
  }

  Widget _chip(String value, String label, Color color, TextStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text('$value $label', style: style.copyWith(color: color.withOpacity(0.8))),
    );
  }
}


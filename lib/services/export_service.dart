import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/contacto.dart';

class ExportService {
  Future<void> exportarCSV(List<Contacto> contactos) async {
    final header = ['nombre', 'apellido', 'telefono', 'direccion', 'ci', 'categoria'];
    final rows = contactos.map((c) => [
      c.nombre, c.apellido, c.telefono, c.direccion ?? '', c.ci ?? '', c.categoriaNombre ?? '',
    ]).toList();

    final csv = const ListToCsvConverter().convert([header, ...rows]);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/guia_telefonica_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], subject: 'Guía Telefónica - CSV', text: '${contactos.length} contactos');
  }

  Future<void> exportarJSON(List<Contacto> contactos) async {
    final data = {
      'metadatos': {'version': '1.0', 'fecha': DateTime.now().toIso8601String(), 'total': contactos.length},
      'contactos': contactos.map((c) => {
        'nombre': c.nombre, 'apellido': c.apellido, 'telefono': c.telefono,
        'direccion': c.direccion, 'ci': c.ci, 'categoria': c.categoriaNombre,
      }).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/guia_telefonica_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);

    await Share.shareXFiles([XFile(file.path)], subject: 'Guía Telefónica - JSON', text: '${contactos.length} contactos');
  }
}

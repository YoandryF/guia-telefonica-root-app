import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/contacto.dart';

class ExportService {
  Future<void> exportarCSV(List<Contacto> contactos) async {
    final header = ['nombre', 'apellido', 'telefono', 'direccion', 'ci', 'categoria', 'provincia', 'municipio', 'pais'];
    final rows = contactos.map((c) => [
      c.nombre, c.apellido, c.telefono, c.direccion ?? '', c.ci ?? '',
      c.categoriaNombre ?? '', c.provincia ?? '', c.municipio ?? '', c.pais ?? 'Cuba',
    ]).toList();

    final csv = const ListToCsvConverter().convert([header, ...rows]);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/guia_telefonica_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(file.path)], subject: 'Guía Telefónica - CSV', text: '${contactos.length} contactos');
  }

  Future<void> exportarJSON(List<Contacto> contactos) async {
    final data = {
      'metadatos': {'version': '1.1', 'fecha': DateTime.now().toIso8601String(), 'total': contactos.length},
      'contactos': contactos.map((c) => {
        'nombre': c.nombre, 'apellido': c.apellido, 'telefono': c.telefono,
        'direccion': c.direccion, 'ci': c.ci, 'categoria': c.categoriaNombre,
        'provincia': c.provincia, 'municipio': c.municipio, 'pais': c.pais,
      }).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/guia_telefonica_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);

    await Share.shareXFiles([XFile(file.path)], subject: 'Guía Telefónica - JSON', text: '${contactos.length} contactos');
  }

  Future<void> exportarPDF(List<Contacto> contactos) async {
    final pdf = pw.Document();
    final chunks = <List<Contacto>>[];
    for (var i = 0; i < contactos.length; i += 25) {
      chunks.add(contactos.sublist(i, i + 25 > contactos.length ? contactos.length : i + 25));
    }

    for (final chunk in chunks) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Guía Telefónica', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Nombre', 'Teléfono', 'Provincia', 'Municipio', 'Dirección'],
              data: chunk.map((c) => [
                c.nombreCompleto, c.telefono,
                c.provincia ?? '', c.municipio ?? '', c.direccion ?? '',
              ]).toList(),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/guia_telefonica_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], subject: 'Guía Telefónica - PDF', text: '${contactos.length} contactos');
  }
}

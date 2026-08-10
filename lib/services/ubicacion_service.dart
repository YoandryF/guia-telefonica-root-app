import 'dart:convert';
import 'package:flutter/services.dart';

/// Servicio para cargar y consultar ubicaciones de Cuba desde JSON estático
class UbicacionService {
  static List<Map<String, dynamic>>? _provincias;

  /// Cargar datos desde asset (solo una vez)
  static Future<void> init() async {
    if (_provincias != null) return;
    final jsonStr = await rootBundle.loadString('assets/cuba_ubicaciones.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    _provincias = List<Map<String, dynamic>>.from(data['provincias']);
  }

  /// Obtener lista de nombres de provincias
  static List<String> getProvincias() {
    if (_provincias == null) return [];
    return _provincias!.map((p) => p['nombre'] as String).toList();
  }

  /// Obtener municipios de una provincia
  static List<String> getMunicipios(String provincia) {
    if (_provincias == null) return [];
    final prov = _provincias!.firstWhere(
      (p) => p['nombre'] == provincia,
      orElse: () => {'municipios': <String>[]},
    );
    return List<String>.from(prov['municipios']);
  }

  /// Buscar provincias que coincidan con un texto parcial
  static List<String> buscarProvincias(String query) {
    if (query.isEmpty) return getProvincias();
    final q = query.toLowerCase();
    return getProvincias().where((p) => p.toLowerCase().contains(q)).toList();
  }

  /// Buscar municipios que coincidan con un texto parcial
  static List<String> buscarMunicipios(String provincia, String query) {
    final municipios = getMunicipios(provincia);
    if (query.isEmpty) return municipios;
    final q = query.toLowerCase();
    return municipios.where((m) => m.toLowerCase().contains(q)).toList();
  }
}

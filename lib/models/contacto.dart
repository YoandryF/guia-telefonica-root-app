/// Modelo de contacto (Supabase)
class Contacto {
  final String id;
  final String nombre;
  final String apellido;
  final String telefono;
  final String? direccion;
  final String? ci;
  final String estado;
  final String? creadoPor;
  final String? creadoDesde;
  final DateTime? fechaCreacion;
  final DateTime? fechaAprobacion;
  final String? motivoRechazo;
  final String? categoriaId;
  final String? categoriaNombre;
  final String? categoriaIcono;
  final bool tieneReportes;
  final bool reporteConfirmado;
  final String? pais;
  final String? provincia;
  final String? municipio;

  Contacto({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    this.direccion,
    this.ci,
    this.estado = 'pendiente',
    this.creadoPor,
    this.creadoDesde,
    this.fechaCreacion,
    this.fechaAprobacion,
    this.motivoRechazo,
    this.categoriaId,
    this.categoriaNombre,
    this.categoriaIcono,
    this.tieneReportes = false,
    this.reporteConfirmado = false,
    this.pais,
    this.provincia,
    this.municipio,
  });

  factory Contacto.fromJson(Map<String, dynamic> json) {
    final categoria = json['categorias'] as Map<String, dynamic>?;
    return Contacto(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      apellido: json['apellido'] as String,
      telefono: json['telefono'] as String,
      direccion: json['direccion'] as String?,
      ci: json['ci'] as String?,
      estado: json['estado'] as String? ?? 'pendiente',
      creadoPor: json['creado_por'] as String?,
      creadoDesde: json['creado_desde'] as String?,
      fechaCreacion: json['fecha_creacion'] != null
          ? DateTime.tryParse(json['fecha_creacion'])
          : null,
      fechaAprobacion: json['fecha_aprobacion'] != null
          ? DateTime.tryParse(json['fecha_aprobacion'])
          : null,
      motivoRechazo: json['motivo_rechazo'] as String?,
      categoriaId: json['categoria_id'] as String?,
      categoriaNombre: categoria?['nombre'] as String?,
      categoriaIcono: categoria?['icono'] as String?,
      tieneReportes: (json['tiene_reportes'] == 1 || json['tiene_reportes'] == true),
      reporteConfirmado: (json['reporte_confirmado'] == 1 || json['reporte_confirmado'] == true),
      pais: json['pais'] as String?,
      provincia: json['provincia'] as String?,
      municipio: json['municipio'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
        'direccion': direccion,
        'ci': ci,
        'estado': estado,
        'creado_por': creadoPor,
        'creado_desde': creadoDesde,
        'categoria_id': categoriaId,
        'pais': pais,
        'provincia': provincia,
        'municipio': municipio,
      };

  String get nombreCompleto => '$nombre $apellido';

  String? get ubicacionCompleta {
    final partes = <String>[];
    if (municipio != null && municipio!.isNotEmpty) partes.add(municipio!);
    if (provincia != null && provincia!.isNotEmpty) partes.add(provincia!);
    if (pais != null && pais!.isNotEmpty && pais != 'Cuba') partes.add(pais!);
    return partes.isNotEmpty ? partes.join(', ') : null;
  }

  // ─── Lógica de negocio ────────────────────────────────────

  /// Nivel de riesgo derivado del estado de reportes
  NivelRiesgo get nivelRiesgo {
    if (reporteConfirmado) return NivelRiesgo.confirmado;
    if (tieneReportes)     return NivelRiesgo.sospechoso;
    return NivelRiesgo.limpio;
  }

  /// El contacto tiene reportes activos o confirmados
  bool get esRiesgoso => tieneReportes || reporteConfirmado;

  /// El usuario puede reportar este contacto (está aprobado y no es duplicado)
  bool get puedeReportarse => estado == 'aprobado';

  /// El contacto tiene ubicación completa (provincia + municipio)
  bool get tieneUbicacion =>
      (provincia != null && provincia!.isNotEmpty) ||
      (municipio != null && municipio!.isNotEmpty);

  /// Texto de estado legible
  String get estadoLabel {
    switch (estado) {
      case 'aprobado':  return 'Aprobado';
      case 'pendiente': return 'Pendiente';
      case 'rechazado': return 'Rechazado';
      default:          return estado;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Enum de nivel de riesgo — usado en UI para colores e iconos
// ─────────────────────────────────────────────────────────────
enum NivelRiesgo {
  limpio,      // sin reportes
  sospechoso,  // tiene reportes pendientes
  confirmado,  // reporte aprobado por admin
}

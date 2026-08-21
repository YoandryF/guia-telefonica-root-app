/// Modelo tipado para reportes — reemplaza Map<String, dynamic>
class Reporte {
  final String id;
  final String contactoId;
  final String motivo;
  final String? descripcion;
  final String estado; // pendiente | revisado | resuelto
  final String? reportadoPor;
  final String? reportadoDesde;
  final DateTime? fechaReporte;
  final DateTime? fechaResolucion;
  final String? notaAdmin;
  final int? evidenciaMsgId;

  // Datos del contacto (join)
  final String? contactoNombre;
  final String? contactoTelefono;

  const Reporte({
    required this.id,
    required this.contactoId,
    required this.motivo,
    this.descripcion,
    required this.estado,
    this.reportadoPor,
    this.reportadoDesde,
    this.fechaReporte,
    this.fechaResolucion,
    this.notaAdmin,
    this.evidenciaMsgId,
    this.contactoNombre,
    this.contactoTelefono,
  });

  factory Reporte.fromJson(Map<String, dynamic> json) {
    final contacto = json['contactos'] as Map<String, dynamic>?;
    return Reporte(
      id:              json['id'] as String,
      contactoId:      json['contacto_id'] as String,
      motivo:          json['motivo'] as String? ?? '',
      descripcion:     json['descripcion'] as String?,
      estado:          json['estado'] as String? ?? 'pendiente',
      reportadoPor:    json['reportado_por'] as String?,
      reportadoDesde:  json['reportado_desde'] as String?,
      fechaReporte:    json['fecha_reporte'] != null
                         ? DateTime.tryParse(json['fecha_reporte']) : null,
      fechaResolucion: json['fecha_resolucion'] != null
                         ? DateTime.tryParse(json['fecha_resolucion']) : null,
      notaAdmin:       json['nota_admin'] as String?,
      evidenciaMsgId:  json['evidencia_msg_id'] as int?,
      contactoNombre:  contacto?['nombre'] != null && contacto?['apellido'] != null
                         ? '${contacto!['nombre']} ${contacto['apellido']}'
                         : contacto?['nombre'] as String?,
      contactoTelefono: contacto?['telefono'] as String?,
    );
  }

  // ─── Lógica de negocio ────────────────────────────────────

  bool get esPendiente  => estado == 'pendiente';
  bool get esAprobado   => estado == 'revisado';
  bool get esDesestimado=> estado == 'resuelto';
  bool get tieneEvidencia => evidenciaMsgId != null;

  String get estadoLabel {
    switch (estado) {
      case 'revisado':  return 'Aprobado';
      case 'resuelto':  return 'Desestimado';
      case 'pendiente': return 'Pendiente';
      default:          return estado;
    }
  }

  String get motivoLabel {
    switch (motivo) {
      case 'spam':              return 'Spam';
      case 'numero_incorrecto': return 'Número incorrecto';
      case 'no_existe':         return 'No existe';
      case 'duplicado':         return 'Duplicado';
      case 'otro':              return 'Otro';
      default:                  return motivo;
    }
  }
}

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
      };

  String get nombreCompleto => '$nombre $apellido';
}

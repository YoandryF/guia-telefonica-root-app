/// Modelo tipado para usuarios verificados en Telegram
class UsuarioTelegram {
  final String chatId;
  final String? nombreUsuario;   // @username
  final String? primerNombre;
  final String? ultimoNombre;
  final DateTime? fechaRegistro;
  final DateTime? ultimaInteraccion;
  final int totalReportes;
  final int totalAvales;
  final int totalContactos;
  final double? trustPct;
  final int restriccionesActivas;
  final bool baneado;

  const UsuarioTelegram({
    required this.chatId,
    this.nombreUsuario,
    this.primerNombre,
    this.ultimoNombre,
    this.fechaRegistro,
    this.ultimaInteraccion,
    this.totalReportes = 0,
    this.totalAvales = 0,
    this.totalContactos = 0,
    this.trustPct,
    this.restriccionesActivas = 0,
    this.baneado = false,
  });

  factory UsuarioTelegram.fromJson(Map<String, dynamic> json) {
    return UsuarioTelegram(
      chatId:               json['chat_id'] as String,
      nombreUsuario:        json['nombre_usuario'] as String?,
      primerNombre:         json['primer_nombre'] as String?,
      ultimoNombre:         json['ultimo_nombre'] as String?,
      fechaRegistro:        json['fecha_registro'] != null
                              ? DateTime.tryParse(json['fecha_registro']) : null,
      ultimaInteraccion:    json['ultima_interaccion'] != null
                              ? DateTime.tryParse(json['ultima_interaccion']) : null,
      totalReportes:        (json['total_reportes'] as num?)?.toInt() ?? 0,
      totalAvales:          (json['total_avales'] as num?)?.toInt() ?? 0,
      totalContactos:       (json['total_contactos'] as num?)?.toInt() ?? 0,
      trustPct:             (json['trust_pct'] as num?)?.toDouble(),
      restriccionesActivas: (json['restricciones_activas'] as num?)?.toInt() ?? 0,
      baneado:              json['baneado'] == true,
    );
  }

  // ─── Lógica de negocio ────────────────────────────────────

  /// Nombre para mostrar — nombre completo, @username o chatId como fallback
  String get displayName {
    final nombre = '${primerNombre ?? ''} ${ultimoNombre ?? ''}'.trim();
    if (nombre.isNotEmpty) return nombre;
    if (nombreUsuario != null && nombreUsuario!.isNotEmpty) return '@$nombreUsuario';
    return chatId;
  }

  String? get usernameConArroba =>
      nombreUsuario != null && nombreUsuario!.isNotEmpty ? '@$nombreUsuario' : null;

  bool get tieneRestricciones => restriccionesActivas > 0 || baneado;

  bool get esConfiable => (trustPct ?? 0) >= 70;

  String get trustLabel {
    if (trustPct == null) return 'Sin datos';
    if (trustPct! >= 70) return 'Alto (${trustPct!.toStringAsFixed(0)}%)';
    if (trustPct! >= 40) return 'Medio (${trustPct!.toStringAsFixed(0)}%)';
    return 'Bajo (${trustPct!.toStringAsFixed(0)}%)';
  }
}

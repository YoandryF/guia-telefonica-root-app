import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────
// Estado de la sincronización
// ─────────────────────────────────────────────────────────────
enum SyncEstado { idle, preparando, descargando, guardando, completado, error, cancelado }

class SyncState {
  final SyncEstado estado;
  final int descargados;
  final int total;
  final int pagina;
  final int totalPaginas;
  final String? errorMsg;
  final int offsetGuardado; // ← para continuar desde donde falló

  const SyncState({
    this.estado = SyncEstado.idle,
    this.descargados = 0,
    this.total = 0,
    this.pagina = 0,
    this.totalPaginas = 0,
    this.errorMsg,
    this.offsetGuardado = 0,
  });

  bool get enProgreso =>
      estado == SyncEstado.preparando ||
      estado == SyncEstado.descargando ||
      estado == SyncEstado.guardando;

  bool get puedeContinuar =>
      estado == SyncEstado.error && offsetGuardado > 0;

  double get progreso => total > 0 ? (descargados / total).clamp(0.0, 1.0) : 0.0;

  String get mensajeProgreso {
    switch (estado) {
      case SyncEstado.idle:      return 'Sin sincronizar';
      case SyncEstado.preparando: return 'Preparando sincronización...';
      case SyncEstado.descargando:
        return total > 0
            ? 'Descargando $descargados de $total contactos'
            : 'Descargando contactos...';
      case SyncEstado.guardando:  return 'Guardando en dispositivo...';
      case SyncEstado.completado: return 'Sincronización completada ($descargados contactos)';
      case SyncEstado.error:      return 'Error: ${errorMsg ?? "desconocido"}';
      case SyncEstado.cancelado:  return 'Sincronización cancelada';
    }
  }

  SyncState copyWith({
    SyncEstado? estado,
    int? descargados,
    int? total,
    int? pagina,
    int? totalPaginas,
    String? errorMsg,
    int? offsetGuardado,
  }) =>
      SyncState(
        estado:         estado         ?? this.estado,
        descargados:    descargados    ?? this.descargados,
        total:          total          ?? this.total,
        pagina:         pagina         ?? this.pagina,
        totalPaginas:   totalPaginas   ?? this.totalPaginas,
        errorMsg:       errorMsg       ?? this.errorMsg,
        offsetGuardado: offsetGuardado ?? this.offsetGuardado,
      );
}

// ─────────────────────────────────────────────────────────────
// Notifier — controla el estado global de la sync
// ─────────────────────────────────────────────────────────────
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier() : super(const SyncState());

  void setPreparando() {
    state = const SyncState(estado: SyncEstado.preparando);
  }

  void setDescargando(int descargados, int total) {
    state = state.copyWith(
      estado: SyncEstado.descargando,
      descargados: descargados,
      total: total,
    );
  }

  void setGuardando() {
    state = state.copyWith(estado: SyncEstado.guardando);
  }

  void setCompletado(int total) {
    state = SyncState(
      estado: SyncEstado.completado,
      descargados: total,
      total: total,
    );
  }

  void setError(String msg, {int offsetGuardado = 0}) {
    state = state.copyWith(
      estado: SyncEstado.error,
      errorMsg: msg,
      offsetGuardado: offsetGuardado,
    );
  }

  void setCancelado() {
    state = state.copyWith(estado: SyncEstado.cancelado);
  }

  void reset() {
    state = const SyncState();
  }
}

// Provider global — accesible desde cualquier widget
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (ref) => SyncNotifier(),
);

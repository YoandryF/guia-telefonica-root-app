import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncEstado { idle, preparando, descargando, guardando, completado, error, cancelado }

class SyncState {
  final SyncEstado estado;
  final int descargados;
  final int total;
  final String? errorMsg;
  // Cursor keyset para reanudar desde donde falló
  final String? cursorNombre;
  final String? cursorId;

  const SyncState({
    this.estado = SyncEstado.idle,
    this.descargados = 0,
    this.total = 0,
    this.errorMsg,
    this.cursorNombre,
    this.cursorId,
  });

  bool get enProgreso =>
      estado == SyncEstado.preparando ||
      estado == SyncEstado.descargando ||
      estado == SyncEstado.guardando;

  bool get puedeContinuar =>
      estado == SyncEstado.error && cursorNombre != null;

  double get progreso => total > 0 ? (descargados / total).clamp(0.0, 1.0) : 0.0;

  String get mensajeProgreso {
    switch (estado) {
      case SyncEstado.idle:       return 'Sin sincronizar';
      case SyncEstado.preparando: return 'Preparando sincronización...';
      case SyncEstado.descargando:
        return total > 0
            ? 'Sincronizando $descargados de $total contactos'
            : 'Sincronizando contactos...';
      case SyncEstado.guardando:  return 'Finalizando sincronización...';
      case SyncEstado.completado: return 'Sincronización completada ($descargados contactos)';
      case SyncEstado.error:
        return descargados > 0
            ? 'Error al sincronizar — $descargados guardados. Toca Continuar'
            : 'Error al sincronizar — toca Continuar para reanudar';
      case SyncEstado.cancelado:  return 'Sincronización cancelada';
    }
  }

  SyncState copyWith({
    SyncEstado? estado,
    int? descargados,
    int? total,
    String? errorMsg,
    String? cursorNombre,
    String? cursorId,
  }) =>
      SyncState(
        estado:       estado       ?? this.estado,
        descargados:  descargados  ?? this.descargados,
        total:        total        ?? this.total,
        errorMsg:     errorMsg     ?? this.errorMsg,
        cursorNombre: cursorNombre ?? this.cursorNombre,
        cursorId:     cursorId     ?? this.cursorId,
      );
}

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier() : super(const SyncState());

  void setPreparando() {
    // Preservar cursor por si venimos de error — para Continuar
    state = state.copyWith(
      estado: SyncEstado.preparando,
      descargados: 0,
      total: 0,
      errorMsg: null,
    );
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

  void setError(String msg, {String? cursorNombre, String? cursorId}) {
    state = state.copyWith(
      estado:       SyncEstado.error,
      errorMsg:     msg,
      cursorNombre: cursorNombre,
      cursorId:     cursorId,
    );
  }

  void setCancelado() {
    state = state.copyWith(estado: SyncEstado.cancelado);
  }

  void reset() {
    state = const SyncState();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (ref) => SyncNotifier(),
);

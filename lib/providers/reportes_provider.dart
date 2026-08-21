import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/reportes_repository.dart';
import 'admin_session_provider.dart';

// --- Estado ---

class ReportesState {
  final List<Map<String, dynamic>> reportesPendientes;
  final bool loading;
  final String? error;

  const ReportesState({
    this.reportesPendientes = const [],
    this.loading = false,
    this.error,
  });

  ReportesState copyWith({
    List<Map<String, dynamic>>? reportesPendientes,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return ReportesState(
      reportesPendientes: reportesPendientes ?? this.reportesPendientes,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// --- Notifier ---

class ReportesNotifier extends AsyncNotifier<ReportesState> {
  final ReportesRepository _repo = ReportesRepository();

  @override
  Future<ReportesState> build() async {
    return _cargar();
  }

  Future<ReportesState> _cargar() async {
    try {
      final reportes = await _repo.getPendientes();
      return ReportesState(reportesPendientes: reportes, loading: false);
    } catch (e) {
      return ReportesState(loading: false, error: e.toString());
    }
  }

  Future<void> cargar() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _cargar());
  }

  Future<void> aprobar(String id) async {
    try {
      await _repo.aprobar(id);
      state = AsyncValue.data(await _cargar());
    } catch (e) {
      final current = state.valueOrNull ?? const ReportesState();
      state = AsyncValue.data(current.copyWith(error: e.toString()));
    }
  }

  Future<void> rechazar(String id, String motivo) async {
    try {
      await _repo.desestimar(id, notaAdmin: motivo);
      state = AsyncValue.data(await _cargar());
    } catch (e) {
      final current = state.valueOrNull ?? const ReportesState();
      state = AsyncValue.data(current.copyWith(error: e.toString()));
    }
  }

  Future<void> desestimar(String id) async {
    try {
      await _repo.desestimar(id);
      state = AsyncValue.data(await _cargar());
    } catch (e) {
      final current = state.valueOrNull ?? const ReportesState();
      state = AsyncValue.data(current.copyWith(error: e.toString()));
    }
  }
}

// --- Providers ---

final reportesProvider =
    AsyncNotifierProvider<ReportesNotifier, ReportesState>(
  ReportesNotifier.new,
);

final misReportesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(adminSessionProvider);
  if (session.adminId == null || session.adminId!.isEmpty) return [];
  return ReportesRepository().getMisReportes(session.adminId!);
});

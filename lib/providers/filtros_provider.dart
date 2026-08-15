import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Estado ---

class FiltrosState {
  final String query;
  final String? categoriaId;
  final bool soloReportados;
  final String ordenPor;

  const FiltrosState({
    this.query = '',
    this.categoriaId,
    this.soloReportados = false,
    this.ordenPor = 'nombre',
  });

  FiltrosState copyWith({
    String? query,
    String? categoriaId,
    bool clearCategoria = false,
    bool? soloReportados,
    String? ordenPor,
  }) {
    return FiltrosState(
      query: query ?? this.query,
      categoriaId: clearCategoria ? null : (categoriaId ?? this.categoriaId),
      soloReportados: soloReportados ?? this.soloReportados,
      ordenPor: ordenPor ?? this.ordenPor,
    );
  }

  bool get tienesFiltrosActivos =>
      query.isNotEmpty ||
      categoriaId != null ||
      soloReportados ||
      ordenPor != 'nombre';
}

// --- Notifier ---

class FiltrosNotifier extends StateNotifier<FiltrosState> {
  FiltrosNotifier() : super(const FiltrosState()) {
    _cargarDesdePrefs();
  }

  static const _prefKeyCategoria = 'filtros_categoria_id';
  static const _prefKeySoloReportados = 'filtros_solo_reportados';
  static const _prefKeyOrden = 'filtros_orden_por';

  Future<void> _cargarDesdePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      categoriaId: prefs.getString(_prefKeyCategoria),
      soloReportados: prefs.getBool(_prefKeySoloReportados) ?? false,
      ordenPor: prefs.getString(_prefKeyOrden) ?? 'nombre',
    );
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.categoriaId != null) {
      await prefs.setString(_prefKeyCategoria, state.categoriaId!);
    } else {
      await prefs.remove(_prefKeyCategoria);
    }
    await prefs.setBool(_prefKeySoloReportados, state.soloReportados);
    await prefs.setString(_prefKeyOrden, state.ordenPor);
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    // No persistir el query — es efímero
  }

  void setCategoria(String? categoriaId) {
    state = state.copyWith(
      categoriaId: categoriaId,
      clearCategoria: categoriaId == null,
    );
    _persistir();
  }

  void toggleSoloReportados() {
    state = state.copyWith(soloReportados: !state.soloReportados);
    _persistir();
  }

  void setOrden(String orden) {
    state = state.copyWith(ordenPor: orden);
    _persistir();
  }

  void limpiar() {
    state = const FiltrosState();
    _persistir();
  }
}

// --- Provider ---

final filtrosProvider = StateNotifierProvider<FiltrosNotifier, FiltrosState>(
  (ref) => FiltrosNotifier(),
);

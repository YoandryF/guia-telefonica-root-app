import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- Estado ---

class FiltrosState {
  final String query;
  final String? categoriaId;
  final bool soloReportados;
  final String ordenPor;
  final String? provincia;   // ← agregado
  final String? municipio;   // ← agregado

  const FiltrosState({
    this.query = '',
    this.categoriaId,
    this.soloReportados = false,
    this.ordenPor = 'nombre',
    this.provincia,
    this.municipio,
  });

  FiltrosState copyWith({
    String? query,
    String? categoriaId,
    bool clearCategoria = false,
    bool? soloReportados,
    String? ordenPor,
    String? provincia,
    bool clearProvincia = false,
    String? municipio,
    bool clearMunicipio = false,
  }) {
    return FiltrosState(
      query:         query          ?? this.query,
      categoriaId:   clearCategoria ? null : (categoriaId ?? this.categoriaId),
      soloReportados: soloReportados ?? this.soloReportados,
      ordenPor:      ordenPor       ?? this.ordenPor,
      provincia:     clearProvincia ? null : (provincia ?? this.provincia),
      municipio:     clearMunicipio ? null : (municipio ?? this.municipio),
    );
  }

  bool get tienesFiltrosActivos =>
      query.isNotEmpty ||
      categoriaId != null ||
      soloReportados ||
      ordenPor != 'nombre' ||
      provincia != null ||
      municipio != null;

  int get contadorFiltrosActivos {
    int n = 0;
    if (categoriaId != null)  n++;
    if (soloReportados)        n++;
    if (provincia != null)     n++;
    if (municipio != null)     n++;
    return n;
  }
}

// --- Notifier ---

class FiltrosNotifier extends StateNotifier<FiltrosState> {
  FiltrosNotifier() : super(const FiltrosState()) {
    _cargarDesdePrefs();
  }

  static const _prefKeyCategoria     = 'filtros_categoria_id';
  static const _prefKeySoloReportados= 'filtros_solo_reportados';
  static const _prefKeyOrden         = 'filtros_orden_por';
  static const _prefKeyProvincia     = 'filtros_provincia';
  static const _prefKeyMunicipio     = 'filtros_municipio';

  Future<void> _cargarDesdePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = state.copyWith(
      categoriaId:    prefs.getString(_prefKeyCategoria),
      soloReportados: prefs.getBool(_prefKeySoloReportados) ?? false,
      ordenPor:       prefs.getString(_prefKeyOrden) ?? 'nombre',
      provincia:      prefs.getString(_prefKeyProvincia),
      municipio:      prefs.getString(_prefKeyMunicipio),
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
    if (state.provincia != null) {
      await prefs.setString(_prefKeyProvincia, state.provincia!);
    } else {
      await prefs.remove(_prefKeyProvincia);
    }
    if (state.municipio != null) {
      await prefs.setString(_prefKeyMunicipio, state.municipio!);
    } else {
      await prefs.remove(_prefKeyMunicipio);
    }
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    // query es efímero — no persistir
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

  void setProvincia(String? provincia) {
    state = state.copyWith(
      provincia:     provincia,
      clearProvincia: provincia == null,
      municipio:     null,
      clearMunicipio: true,   // al cambiar provincia, limpiar municipio
    );
    _persistir();
  }

  void setMunicipio(String? municipio) {
    state = state.copyWith(
      municipio:     municipio,
      clearMunicipio: municipio == null,
    );
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

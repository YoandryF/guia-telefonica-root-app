import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contacto.dart';
import '../repositories/contactos_repository.dart';
import 'filtros_provider.dart';

// --- Estado ---

class ContactosState {
  final List<Contacto> contactos;
  final int paginaActual;
  final int total;
  final bool loading;

  const ContactosState({
    this.contactos = const [],
    this.paginaActual = 0,
    this.total = 0,
    this.loading = false,
  });

  ContactosState copyWith({
    List<Contacto>? contactos,
    int? paginaActual,
    int? total,
    bool? loading,
  }) {
    return ContactosState(
      contactos: contactos ?? this.contactos,
      paginaActual: paginaActual ?? this.paginaActual,
      total: total ?? this.total,
      loading: loading ?? this.loading,
    );
  }
}

// --- Notifier ---

class ContactosNotifier extends AsyncNotifier<ContactosState> {
  static const int _pageSize = 50;
  final ContactosRepository _repo = ContactosRepository();

  @override
  Future<ContactosState> build() async {
    return _cargarPagina(0);
  }

  Future<ContactosState> _cargarPagina(int pagina) async {
    final filtros = ref.read(filtrosProvider);

    final total = await _repo.count(
      categoriaId: filtros.categoriaId,
      soloReportados: filtros.soloReportados,
    );

    final contactos = await _repo.getPaginado(
      offset: pagina * _pageSize,
      limit: _pageSize,
      categoriaId: filtros.categoriaId,
      soloReportados: filtros.soloReportados,
    );

    return ContactosState(
      contactos: contactos,
      paginaActual: pagina,
      total: total,
      loading: false,
    );
  }

  /// Carga la siguiente página
  Future<void> siguientePagina() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final maxPagina = (current.total / _pageSize).ceil() - 1;
    if (current.paginaActual >= maxPagina) return;

    state = const AsyncValue.loading();
    state = AsyncValue.data(await _cargarPagina(current.paginaActual + 1));
  }

  /// Carga la página anterior
  Future<void> paginaAnterior() async {
    final current = state.valueOrNull;
    if (current == null || current.paginaActual <= 0) return;

    state = const AsyncValue.loading();
    state = AsyncValue.data(await _cargarPagina(current.paginaActual - 1));
  }

  /// Ir a una página específica
  Future<void> irAPagina(int pagina) async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _cargarPagina(pagina));
  }

  /// Recargar desde la primera página
  Future<void> recargar() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _cargarPagina(0));
  }
}

// --- Providers ---

final contactosProvider =
    AsyncNotifierProvider<ContactosNotifier, ContactosState>(
  ContactosNotifier.new,
);

/// Provider derivado que aplica filtro de texto (query) sobre los contactos
/// ya cargados en la página actual.
final contactosFiltradosProvider = Provider<List<Contacto>>((ref) {
  final contactosAsync = ref.watch(contactosProvider);
  final filtros = ref.watch(filtrosProvider);

  return contactosAsync.when(
    data: (state) {
      if (filtros.query.isEmpty) return state.contactos;

      final q = filtros.query.toLowerCase();
      return state.contactos.where((c) {
        return c.nombre.toLowerCase().contains(q) ||
            c.apellido.toLowerCase().contains(q) ||
            c.telefono.contains(q) ||
            (c.ci?.contains(q) ?? false) ||
            (c.provincia?.toLowerCase().contains(q) ?? false) ||
            (c.municipio?.toLowerCase().contains(q) ?? false);
      }).toList();
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

final busquedaContactosProvider =
    FutureProvider.family<List<Contacto>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  return ContactosRepository().buscar(query.trim());
});

import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';

/// Repositorio de contactos — unifica lectura local (SQLite) y escritura remota (Supabase).
/// Las pantallas usan este repositorio en vez de importar los servicios directamente.
class ContactosRepository {
  final LocalDatabaseService _local;
  final SupabaseService _remote;

  ContactosRepository({LocalDatabaseService? local, SupabaseService? remote})
      : _local = local ?? LocalDatabaseService(),
        _remote = remote ?? SupabaseService();

  // ─── Lectura local (SQLite) ────────────────────────────────────────

  Future<List<Contacto>> getPaginado({
    int offset = 0,
    int limit = 50,
    String? categoriaId,
    bool soloReportados = false,
    String? provincia,
    String? municipio,
  }) {
    return _local.getContactosPaginados(
      offset: offset,
      limit: limit,
      categoriaId: categoriaId,
      soloReportados: soloReportados,
      provincia: provincia,
      municipio: municipio,
    );
  }

  Future<Contacto?> getById(String id) async {
    final contactos = await _local.getContactosPorIds([id]);
    return contactos.isNotEmpty ? contactos.first : null;
  }

  Future<Contacto?> buscarPorTelefono(String telefono) {
    return _local.buscarPorTelefono(telefono);
  }

  Future<List<Contacto>> buscar(String query, {int offset = 0, int limit = 50}) {
    if (query.trim().isEmpty) return Future.value([]);
    return _local.buscarContactosPaginados(query.trim(), offset: offset, limit: limit);
  }

  Future<int> count({
    String? categoriaId,
    bool soloReportados = false,
    String? provincia,
    String? municipio,
  }) {
    return _local.countContactos(
      categoriaId: categoriaId,
      soloReportados: soloReportados,
      provincia: provincia,
      municipio: municipio,
    );
  }

  Future<List<Contacto>> getFavoritos() async {
    final ids = await _local.getFavoritosIds();
    return _local.getContactosPorIds(ids);
  }

  Future<void> guardarBatch(List<Contacto> contactos) {
    return _local.sincronizarBatch(contactos);
  }

  Future<void> eliminarLocal(String id) {
    return _local.eliminarContacto(id);
  }

  // ─── Escritura remota (Supabase) ───────────────────────────────────

  Future<Map<String, dynamic>> agregar({
    required String nombre,
    required String apellido,
    required String telefono,
    String? direccion,
    String? ci,
    String? provincia,
    String? municipio,
    String? creadoPor,
  }) {
    return _remote.registrarContacto(
      nombre: nombre,
      apellido: apellido,
      telefono: telefono,
      direccion: direccion,
      ci: ci,
      provincia: provincia,
      municipio: municipio,
      dispositivoId: creadoPor,
    );
  }

  Future<Map<String, dynamic>> aprobar(String id) async {
    try {
      await _remote.aprobarContacto(id);
      return {'error': null};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> rechazar(String id, String motivo) async {
    try {
      await _remote.rechazarContacto(id, motivo);
      return {'error': null};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> eliminar(String id) async {
    try {
      await _remote.eliminarContacto(id);
      return {'error': null};
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}

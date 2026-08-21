import '../services/supabase_service.dart';

/// Repositorio de usuarios — encapsula usuarios Telegram, admins y restricciones.
class UsuariosRepository {
  final SupabaseService _remote;

  UsuariosRepository({SupabaseService? remote})
      : _remote = remote ?? SupabaseService();

  Future<Map<String, dynamic>> getUsuarios({
    String query = '',
    int offset = 0,
    int limit = 20,
  }) {
    return _remote.getUsuariosAdmin(query: query, offset: offset, limit: limit);
  }

  Future<Map<String, dynamic>> getUsuario360(String telegramUserId) {
    return _remote.getUsuario360(telegramUserId);
  }

  Future<Map<String, dynamic>> agregarRestriccion({
    required String telegramUserId,
    required String funcionalidad,
    required String motivo,
    required String creadoPor,
    DateTime? fechaFin,
  }) {
    return _remote.agregarRestriccion(
      telegramUserId: telegramUserId,
      funcionalidad: funcionalidad,
      motivo: motivo,
      creadoPor: creadoPor,
      fechaFin: fechaFin,
    );
  }

  Future<Map<String, dynamic>> quitarRestriccion(String restriccionId) {
    return _remote.quitarRestriccion(restriccionId);
  }

  Future<List<Map<String, dynamic>>> getAdmins() {
    return _remote.getAdmins();
  }

  Future<Map<String, dynamic>> crearAdmin({
    required String email,
    required String password,
    required String nombre,
  }) async {
    try {
      await _remote.crearAdmin(email: email, password: password, nombre: nombre);
      return {'error': null};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<void> desactivarAdmin(String email) {
    return _remote.desactivarAdmin(email);
  }

  Future<Map<String, dynamic>> getAnalytics() {
    return _remote.getAnalyticsAdmin();
  }

  Future<Map<String, dynamic>> getDashboardStats() {
    return _remote.getDashboardStats();
  }
}

import '../services/supabase_service.dart';

/// Repositorio de reportes — encapsula toda la lógica de reportes delegando a SupabaseService.
class ReportesRepository {
  final SupabaseService _remote;

  ReportesRepository({SupabaseService? remote})
      : _remote = remote ?? SupabaseService();

  Future<List<Map<String, dynamic>>> getPendientes() {
    return _remote.getReportesPendientes();
  }

  Future<List<Map<String, dynamic>>> getMisReportes(String telegramUserId) {
    return _remote.getMisReportes(telegramUserId);
  }

  Future<void> aprobar(String id, {String? notaAdmin}) {
    return _remote.aprobarReporte(id, notaAdmin: notaAdmin);
  }

  Future<void> desestimar(String id, {String? notaAdmin}) {
    return _remote.desestimarReporte(id, notaAdmin: notaAdmin);
  }

  Future<void> aprobarBulk(List<String> ids) {
    return _remote.aprobarReportesBulk(ids);
  }

  Future<void> desestimarBulk(List<String> ids) {
    return _remote.desestimarReportesBulk(ids);
  }

  Future<Map<String, dynamic>> insertar({
    required String contactoId,
    required String motivo,
    String? descripcion,
    String? reportadoPor,
    String? dispositivoId,
    String? telegramUserId,
  }) {
    return _remote.reportarContacto(
      contactoId: contactoId,
      motivo: motivo,
      descripcion: descripcion,
      dispositivoId: dispositivoId,
      telegramUserId: telegramUserId,
    );
  }

  Future<Set<String>> getIdsConReportes() {
    return _remote.getContactosConReportes();
  }

  Future<Map<String, dynamic>> getInfoReportes(String contactoId) {
    return _remote.getInfoReportes(contactoId);
  }

  Future<int> contarPendientes() async {
    final pendientes = await _remote.getReportesPendientes();
    return pendientes.length;
  }

  // Métodos adicionales para reportes_admin_screen
  Future<List<Map<String, dynamic>>> getAgrupados({String filtro = 'todos', String orden = 'recientes'}) {
    return _remote.getReportesAgrupados(filtro: filtro, orden: orden);
  }

  Future<List<Map<String, dynamic>>> getDeContacto({required String contactoId, String? filtroEstado}) {
    return _remote.getReportesDeContacto(contactoId, filtroEstado: filtroEstado);
  }

  Future<void> eliminar(String id) {
    return _remote.eliminarReporte(id);
  }

  Future<void> reactivar(String id) {
    return _remote.reactivarReporte(id);
  }

  Future<Map<String, dynamic>> getStatsReportador(String identificador) {
    return _remote.getStatsReportador(identificador);
  }
}

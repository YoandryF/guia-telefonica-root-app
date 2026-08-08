import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/contacto.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // === CONTACTOS PÚBLICOS ===

  Future<List<Contacto>> getContactosAprobadosDesde(DateTime? fecha) async {
    var query = _client
        .from('contactos')
        .select('*, categorias(nombre, icono)')
        .eq('estado', 'aprobado')
        .isFilter('deleted_at', null);

    if (fecha != null) {
      query = query.or(
        'fecha_aprobacion.gt.${fecha.toIso8601String()},'
        'ultima_modificacion.gt.${fecha.toIso8601String()}',
      );
    }

    final response = await query.order('nombre');
    return (response as List).map((json) => Contacto.fromJson(json)).toList();
  }

  Future<List<String>> getContactosEliminadosDesde(DateTime fecha) async {
    final response = await _client
        .from('contactos')
        .select('id')
        .not('deleted_at', 'is', null)
        .gt('deleted_at', fecha.toIso8601String());

    return (response as List).map((json) => json['id'] as String).toList();
  }

  Future<Map<String, dynamic>> registrarContacto({
    required String nombre,
    required String apellido,
    required String telefono,
    String? direccion,
    String? ci,
    String? categoriaId,
    String? dispositivoId,
  }) async {
    try {
      final response = await _client.from('contactos').insert({
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
        'direccion': direccion,
        'ci': ci,
        'categoria_id': categoriaId,
        'estado': 'pendiente',
        'creado_desde': 'app',
        'dispositivo_id': dispositivoId,
      }).select();

      return {'data': response.first, 'error': null};
    } catch (e) {
      return {'data': null, 'error': e.toString()};
    }
  }

  // === CATEGORÍAS ===

  Future<List<Map<String, dynamic>>> getCategorias() async {
    final response = await _client
        .from('categorias')
        .select()
        .eq('activa', true)
        .order('nombre');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> crearCategoria({required String nombre, String? icono, String? color}) async {
    await _client.from('categorias').insert({
      'nombre': nombre,
      'icono': icono ?? '📋',
      'color': color,
      'activa': true,
    });
  }

  Future<void> editarCategoria({required String id, required String nombre, String? icono, String? color}) async {
    await _client.from('categorias').update({
      'nombre': nombre,
      'icono': icono,
      'color': color,
    }).eq('id', id);
  }

  Future<void> desactivarCategoria(String id) async {
    await _client.from('categorias').update({'activa': false}).eq('id', id);
  }

  // === ADMIN ===

  Future<List<Contacto>> getContactosPendientes() async {
    final response = await _client
        .from('contactos')
        .select('*, categorias(nombre, icono)')
        .eq('estado', 'pendiente')
        .isFilter('deleted_at', null)
        .order('fecha_creacion');

    return (response as List).map((json) => Contacto.fromJson(json)).toList();
  }

  Future<List<Contacto>> getContactosPorEstado(
    String estado, {
    int page = 0,
    int limit = 20,
    String? query,
  }) async {
    var request = _client
        .from('contactos')
        .select('*, categorias(nombre, icono)')
        .isFilter('deleted_at', null);

    if (estado != 'todos') {
      request = request.eq('estado', estado);
    }

    if (query != null && query.length >= 3) {
      request = request.or(
        'nombre.ilike.%$query%,'
        'apellido.ilike.%$query%,'
        'telefono.ilike.%$query%,'
        'ci.ilike.%$query%',
      );
    }

    final response = await request
        .order('nombre')
        .range(page * limit, (page + 1) * limit - 1);

    return (response as List).map((json) => Contacto.fromJson(json)).toList();
  }

  Future<void> aprobarContacto(String id) async {
    await _client.from('contactos').update({
      'estado': 'aprobado',
      'fecha_aprobacion': DateTime.now().toIso8601String(),
      'ultima_modificacion': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> rechazarContacto(String id, String motivo) async {
    await _client.from('contactos').update({
      'estado': 'rechazado',
      'motivo_rechazo': motivo,
      'ultima_modificacion': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> editarContacto(String id, Map<String, dynamic> datos) async {
    datos['ultima_modificacion'] = DateTime.now().toIso8601String();
    await _client.from('contactos').update(datos).eq('id', id);
  }

  Future<void> eliminarContacto(String id) async {
    await _client.from('contactos').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<Map<String, int>> getEstadisticas() async {
    final aprobados = await _client
        .from('contactos')
        .select()
        .eq('estado', 'aprobado')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);

    final pendientes = await _client
        .from('contactos')
        .select()
        .eq('estado', 'pendiente')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);

    final rechazados = await _client
        .from('contactos')
        .select()
        .eq('estado', 'rechazado')
        .isFilter('deleted_at', null)
        .count(CountOption.exact);

    return {
      'aprobados': aprobados.count,
      'pendientes': pendientes.count,
      'rechazados': rechazados.count,
    };
  }

  // === CONTACTOS CON REPORTES ===

  Future<Set<String>> getContactosConReportes() async {
    try {
      final response = await _client.rpc('get_contactos_reportados');
      final list = List<Map<String, dynamic>>.from(response);
      return list.map((r) => r['contacto_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  // === VALORACIONES ===

  Future<void> valorarContacto(String contactoId, int estrellas, String? dispositivoId) async {
    await _client.from('valoraciones').upsert({
      'contacto_id': contactoId,
      'estrellas': estrellas,
      'dispositivo_id': dispositivoId ?? 'unknown',
    });
  }

  Future<double> getPromedioValoracion(String contactoId) async {
    final response = await _client
        .from('valoraciones')
        .select('estrellas')
        .eq('contacto_id', contactoId);
    final list = List<Map<String, dynamic>>.from(response);
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, r) => acc + (r['estrellas'] as int));
    return sum / list.length;
  }

  // === REPORTES ===

  Future<Map<String, dynamic>> reportarContacto({
    required String contactoId,
    required String motivo,
    String? descripcion,
    String? dispositivoId,
  }) async {
    try {
      final result = await _client.rpc('insertar_reporte', params: {
        'p_contacto_id': contactoId,
        'p_motivo': motivo,
        'p_descripcion': descripcion,
        'p_reportado_desde': 'app',
        'p_dispositivo_id': dispositivoId,
      });
      final status = result.toString();
      if (status == 'OK') return {'error': null};
      if (status == 'LIMITE') return {'error': 'Has alcanzado el límite de reportes por hoy'};
      if (status == 'BANEADO') return {'error': 'No tienes permiso para reportar'};
      return {'error': status};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<int> getConteoReportes(String contactoId) async {
    final response = await _client
        .from('reportes')
        .select()
        .eq('contacto_id', contactoId)
        .or('estado.eq.pendiente,estado.eq.revisado')
        .count(CountOption.exact);
    return response.count;
  }

  Future<Map<String, dynamic>> getInfoReportes(String contactoId) async {
    final pendientes = await _client
        .from('reportes')
        .select()
        .eq('contacto_id', contactoId)
        .eq('estado', 'pendiente')
        .count(CountOption.exact);
    final aprobados = await _client
        .from('reportes')
        .select()
        .eq('contacto_id', contactoId)
        .eq('estado', 'revisado')
        .count(CountOption.exact);
    final mostrar = aprobados.count >= 1 || pendientes.count >= 3;
    return {
      'pendientes': pendientes.count,
      'aprobados': aprobados.count,
      'mostrarBadge': mostrar,
      'esVerificado': aprobados.count >= 1,
    };
  }

  Future<List<Map<String, dynamic>>> getReportesAgrupados({String filtro = 'todos', String orden = 'mas_reportes'}) async {
    final response = await _client.rpc('get_reportes_agrupados', params: {'filtro': filtro, 'orden': orden});
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getReportesPendientes() async {
    final response = await _client
        .from('reportes')
        .select('*, contactos(nombre, apellido, telefono)')
        .eq('estado', 'pendiente')
        .order('fecha_reporte');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> desestimarReporte(String reporteId) async {
    await _client.from('reportes').update({'estado': 'resuelto', 'fecha_resolucion': DateTime.now().toIso8601String()}).eq('id', reporteId);
  }

  Future<void> aprobarReporte(String reporteId) async {
    await _client.from('reportes').update({'estado': 'revisado', 'fecha_resolucion': DateTime.now().toIso8601String()}).eq('id', reporteId);
  }

  Future<List<Map<String, dynamic>>> getReportesResueltos() async {
    final response = await _client
        .from('reportes')
        .select('*, contactos(nombre, apellido, telefono)')
        .eq('estado', 'resuelto')
        .order('fecha_resolucion', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getReportesPorEstado(String estado) async {
    final response = await _client
        .from('reportes')
        .select('*, contactos(nombre, apellido, telefono)')
        .eq('estado', estado)
        .order('fecha_reporte', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getReportesDeContacto(String contactoId) async {
    final response = await _client
        .from('reportes')
        .select('*')
        .eq('contacto_id', contactoId)
        .order('fecha_reporte', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> eliminarReporte(String reporteId) async {
    await _client.from('reportes').delete().eq('id', reporteId);
  }

  Future<void> reactivarReporte(String reporteId) async {
    await _client.from('reportes').update({'estado': 'pendiente', 'fecha_resolucion': null}).eq('id', reporteId);
  }

  Future<void> banearReportador(String identificador, {String? motivo}) async {
    await _client.from('usuarios_baneados').insert({
      'identificador': identificador,
      'motivo': motivo ?? 'Abuso de reportes',
    });
  }

  Future<void> desbanearReportador(String identificador) async {
    await _client.from('usuarios_baneados').delete().eq('identificador', identificador);
  }

  // === AUTH ADMIN ===

  Future<bool> loginAdmin(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> logoutAdmin() async {
    await _client.auth.signOut();
  }

  bool get isAdmin => _client.auth.currentUser != null;
}

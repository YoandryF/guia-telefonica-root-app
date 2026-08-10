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
    String? pais,
    String? provincia,
    String? municipio,
  }) async {
    try {
      final data = <String, dynamic>{
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
        'direccion': direccion,
        'ci': ci,
        'categoria_id': categoriaId,
        'estado': 'pendiente',
        'creado_desde': 'app',
        'dispositivo_id': dispositivoId,
      };
      if (provincia != null) data['provincia'] = provincia;
      if (municipio != null) data['municipio'] = municipio;
      if (pais != null) data['pais'] = pais;

      final response = await _client.from('contactos').insert(data).select();

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
        'ci.ilike.%$query%,'
        'provincia.ilike.%$query%,'
        'municipio.ilike.%$query%',
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
    String? telegramUserId,
  }) async {
    try {
      final result = await _client.rpc('insertar_reporte', params: {
        'p_contacto_id': contactoId,
        'p_motivo': motivo,
        'p_descripcion': descripcion,
        'p_reportado_desde': 'app',
        'p_dispositivo_id': dispositivoId,
        'p_telegram_user_id': telegramUserId,
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

  // === AVALES (contra-reportes positivos) ===

  Future<Map<String, dynamic>> avalarContacto(String contactoId, {String? dispositivoId, String? telegramUserId}) async {
    try {
      await _client.from('avales').insert({
        'contacto_id': contactoId,
        'dispositivo_id': dispositivoId,
        'avalado_por': telegramUserId,
      });
      return {'error': null};
    } catch (e) {
      if (e.toString().contains('duplicate')) return {'error': 'Ya avalaste este contacto'};
      return {'error': e.toString()};
    }
  }

  Future<int> getConteoAvales(String contactoId) async {
    final r = await _client.from('avales').select().eq('contacto_id', contactoId).count(CountOption.exact);
    return r.count;
  }

  // === RECLAMOS (derecho a réplica) ===

  Future<Map<String, dynamic>> reclamarContacto(String contactoId, String mensaje, {String? reclamanteId}) async {
    try {
      await _client.from('reclamos').insert({'contacto_id': contactoId, 'mensaje': mensaje, 'reclamante_id': reclamanteId});
      return {'error': null};
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> getReclamosPendientes() async {
    final r = await _client.from('reclamos').select('*, contactos(nombre, apellido, telefono)').eq('estado', 'pendiente').order('fecha');
    return List<Map<String, dynamic>>.from(r);
  }

  Future<void> resolverReclamo(String reclamoId, String estado) async {
    await _client.from('reclamos').update({'estado': estado}).eq('id', reclamoId);
  }

  // === TRUST SCORE ===

  Future<double> getTrustScore(String identificador) async {
    try {
      final aprobados = await _client.from('reportes').select().or('dispositivo_id.eq.$identificador,reportado_por.eq.$identificador').eq('estado', 'revisado').count(CountOption.exact);
      final desestimados = await _client.from('reportes').select().or('dispositivo_id.eq.$identificador,reportado_por.eq.$identificador').eq('estado', 'resuelto').count(CountOption.exact);
      final total = aprobados.count + desestimados.count;
      if (total == 0) return 0.5;
      return aprobados.count / total;
    } catch (_) {
      return 0.5;
    }
  }

  // === CONFIGURACIÓN ===

  Future<String> getConfig(String clave, {String defaultValue = ''}) async {
    try {
      final r = await _client.from('configuracion').select('valor').eq('clave', clave).limit(1);
      final list = List<Map<String, dynamic>>.from(r);
      return list.isNotEmpty ? list.first['valor'] as String : defaultValue;
    } catch (_) {
      return defaultValue;
    }
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

  Future<List<Map<String, dynamic>>> getAdmins() async {
    final response = await _client.from('admins').select().order('fecha_creacion');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> crearAdmin({required String email, required String password, required String nombre}) async {
    final authResponse = await _client.auth.admin.createUser(AdminUserAttributes(email: email, password: password, emailConfirm: true));
    await _client.from('admins').insert({'user_id': authResponse.user!.id, 'email': email, 'nombre_admin': nombre, 'activo': true, 'rol': 'admin'});
  }

  Future<void> desactivarAdmin(String email) async {
    await _client.from('admins').update({'activo': false}).eq('email', email);
  }
}

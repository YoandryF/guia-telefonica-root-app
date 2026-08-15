import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/supabase_service.dart';

// --- Estado ---

class AdminSessionState {
  final bool esAdmin;
  final bool esOwner;
  final String? adminId;
  final String? nombre;

  const AdminSessionState({
    this.esAdmin = false,
    this.esOwner = false,
    this.adminId,
    this.nombre,
  });

  AdminSessionState copyWith({
    bool? esAdmin,
    bool? esOwner,
    String? adminId,
    String? nombre,
    bool clearAdminId = false,
    bool clearNombre = false,
  }) {
    return AdminSessionState(
      esAdmin: esAdmin ?? this.esAdmin,
      esOwner: esOwner ?? this.esOwner,
      adminId: clearAdminId ? null : (adminId ?? this.adminId),
      nombre: clearNombre ? null : (nombre ?? this.nombre),
    );
  }
}

// --- Notifier ---

class AdminSessionNotifier extends StateNotifier<AdminSessionState> {
  AdminSessionNotifier() : super(const AdminSessionState()) {
    verificarSesion();
  }

  final SupabaseService _supabaseService = SupabaseService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _keyAdminId = 'admin_session_id';
  static const _keyNombre = 'admin_session_nombre';
  static const _keyEsOwner = 'admin_session_es_owner';

  /// Inicia sesión como admin usando Supabase Auth
  Future<bool> login(String email, String password) async {
    final exito = await _supabaseService.loginAdmin(email, password);
    if (!exito) return false;

    // Obtener info del admin desde la tabla admins
    final admins = await _supabaseService.getAdmins();
    final adminData = admins.firstWhere(
      (a) => a['email'] == email,
      orElse: () => <String, dynamic>{},
    );

    final adminId = adminData['user_id'] as String? ?? '';
    final nombre = adminData['nombre_admin'] as String? ?? email;
    final rol = adminData['rol'] as String? ?? 'admin';
    final esOwner = rol == 'owner';

    // Persistir en secure storage
    await _storage.write(key: _keyAdminId, value: adminId);
    await _storage.write(key: _keyNombre, value: nombre);
    await _storage.write(key: _keyEsOwner, value: esOwner.toString());

    state = AdminSessionState(
      esAdmin: true,
      esOwner: esOwner,
      adminId: adminId,
      nombre: nombre,
    );

    return true;
  }

  /// Cierra sesión del admin
  Future<void> logout() async {
    await _supabaseService.logoutAdmin();
    await _storage.delete(key: _keyAdminId);
    await _storage.delete(key: _keyNombre);
    await _storage.delete(key: _keyEsOwner);

    state = const AdminSessionState();
  }

  /// Verifica si hay una sesión activa al iniciar
  Future<void> verificarSesion() async {
    // Verificar si Supabase tiene sesión activa
    if (!_supabaseService.isAdmin) {
      // Limpiar storage por si quedó basura
      await _storage.delete(key: _keyAdminId);
      await _storage.delete(key: _keyNombre);
      await _storage.delete(key: _keyEsOwner);
      state = const AdminSessionState();
      return;
    }

    // Recuperar datos guardados
    final adminId = await _storage.read(key: _keyAdminId);
    final nombre = await _storage.read(key: _keyNombre);
    final esOwnerStr = await _storage.read(key: _keyEsOwner);

    if (adminId != null && adminId.isNotEmpty) {
      state = AdminSessionState(
        esAdmin: true,
        esOwner: esOwnerStr == 'true',
        adminId: adminId,
        nombre: nombre,
      );
    } else {
      state = const AdminSessionState();
    }
  }
}

// --- Provider ---

final adminSessionProvider =
    StateNotifierProvider<AdminSessionNotifier, AdminSessionState>(
  (ref) => AdminSessionNotifier(),
);

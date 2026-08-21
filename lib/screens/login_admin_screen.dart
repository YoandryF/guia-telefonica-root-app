import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/router.dart';
import '../providers/admin_session_provider.dart';
import '../services/supabase_service.dart';

class LoginAdminScreen extends ConsumerStatefulWidget {
  const LoginAdminScreen({super.key});
  @override
  ConsumerState<LoginAdminScreen> createState() => _LoginAdminScreenState();
}

class _LoginAdminScreenState extends ConsumerState<LoginAdminScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _supabase = SupabaseService();
  final _storage = const FlutterSecureStorage();
  bool _cargando = false;
  bool _mostrarPassword = false;
  bool _recordar = true;

  @override
  void initState() {
    super.initState();
    _verificarSesion();
    _cargarCredenciales();
  }

  void _verificarSesion() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.adminPanel);
      });
    }
  }

  Future<void> _cargarCredenciales() async {
    final email = await _storage.read(key: 'admin_email');
    final pass = await _storage.read(key: 'admin_pass');
    if (email != null && pass != null) {
      setState(() {
        _emailCtrl.text = email;
        _passwordCtrl.text = pass;
      });
    }
  }

  Future<void> _guardarCredenciales() async {
    if (_recordar) {
      await _storage.write(key: 'admin_email', value: _emailCtrl.text.trim());
      await _storage.write(key: 'admin_pass', value: _passwordCtrl.text);
    }
  }

  Future<void> _login() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) return;
    setState(() => _cargando = true);

    final ok = await _supabase.loginAdmin(_emailCtrl.text.trim(), _passwordCtrl.text);
    setState(() => _cargando = false);
    if (!mounted) return;

    if (ok) {
      await _guardarCredenciales();
      // Notificar al provider global — otras pantallas sabrán que hay sesión admin
      await ref.read(adminSessionProvider.notifier).verificarSesion();
      if (!mounted) return;
      context.go(AppRoutes.adminPanel);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Credenciales incorrectas'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🔐 Admin Login')),
      body: AutofillGroup(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings, size: 64, color: Color(0xFF0284C7)),
              const SizedBox(height: 24),
              TextField(
                controller: _emailCtrl,
                autofillHints: const [AutofillHints.email, AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordCtrl,
                obscureText: !_mostrarPassword,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_mostrarPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(value: _recordar, onChanged: (v) => setState(() => _recordar = v ?? true)),
                  const Text('Recordar credenciales'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _cargando ? null : _login,
                  child: _cargando
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : const Text('INGRESAR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}

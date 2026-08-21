import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/contacto.dart';
import '../screens/acerca_de_screen.dart';
import '../screens/admin_panel_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/avales_pendientes_screen.dart';
import '../screens/contacto_detalle_screen.dart';
import '../screens/exportar_screen.dart';
import '../screens/home_screen.dart';
import '../screens/importar_screen.dart';
import '../screens/invitacion_screen.dart';
import '../screens/lista_negra_screen.dart';
import '../screens/login_admin_screen.dart';
import '../screens/mis_reportes_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/reportes_admin_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/usuario_detalle_screen.dart';
import '../screens/usuarios_admin_screen.dart';

// ─────────────────────────────────────────────────────────────
// Rutas nombradas — una sola fuente de verdad
// ─────────────────────────────────────────────────────────────
class AppRoutes {
  static const splash         = '/';
  static const home           = '/home';
  static const onboarding     = '/onboarding';
  static const contacto       = '/contacto';
  static const listaNegra     = '/lista-negra';
  static const misReportes    = '/mis-reportes';
  static const invitacion     = '/invitacion';
  static const acercaDe      = '/acerca-de';

  // Admin — protección manejada por cada pantalla, no por guards del router
  // (los guards globales causan race condition con verificarSesion async)
  static const adminLogin     = '/admin/login';
  static const adminPanel     = '/admin';
  static const adminReportes  = '/admin/reportes';
  static const adminUsuarios  = '/admin/usuarios';
  static const adminUsuario   = '/admin/usuarios/:telegramId';
  static const adminAnalytics = '/admin/analytics';
  static const adminAvales    = '/admin/avales';
  static const adminExportar  = '/admin/exportar';
  static const adminImportar  = '/admin/importar';
}

// Router sin guards globales — rutas puras
final router = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  routes: [
    GoRoute(path: AppRoutes.splash,      builder: (_, __) => const SplashScreen()),
    GoRoute(path: AppRoutes.home,        builder: (_, __) => const HomeScreen()),
    GoRoute(path: AppRoutes.onboarding,  builder: (_, __) => const OnboardingScreen()),
    GoRoute(
      path: AppRoutes.contacto,
      builder: (_, state) {
        final contacto = state.extra as Contacto?;
        if (contacto == null) return const HomeScreen();
        return ContactoDetalleScreen(contacto: contacto);
      },
    ),
    GoRoute(path: AppRoutes.listaNegra,  builder: (_, __) => const ListaNegraScreen()),
    GoRoute(path: AppRoutes.misReportes, builder: (_, __) => const MisReportesScreen()),
    GoRoute(path: AppRoutes.invitacion,  builder: (_, __) => const InvitacionScreen()),
    GoRoute(path: AppRoutes.acercaDe,    builder: (_, __) => const AcercaDeScreen()),

    // Admin
    GoRoute(path: AppRoutes.adminLogin,     builder: (_, __) => const LoginAdminScreen()),
    GoRoute(path: AppRoutes.adminPanel,     builder: (_, __) => const AdminPanelScreen()),
    GoRoute(path: AppRoutes.adminReportes,  builder: (_, __) => const ReportesAdminScreen()),
    GoRoute(path: AppRoutes.adminUsuarios,  builder: (_, __) => const UsuariosAdminScreen()),
    GoRoute(
      path: AppRoutes.adminUsuario,
      builder: (_, state) => UsuarioDetalleScreen(
        telegramUserId: state.pathParameters['telegramId'] ?? '',
      ),
    ),
    GoRoute(path: AppRoutes.adminAnalytics, builder: (_, __) => const AnalyticsScreen()),
    GoRoute(path: AppRoutes.adminAvales,    builder: (_, __) => const AvalesPendientesScreen()),
    GoRoute(path: AppRoutes.adminExportar,  builder: (_, __) => const ExportarScreen()),
    GoRoute(path: AppRoutes.adminImportar,  builder: (_, __) => const ImportarScreen()),
  ],
  errorBuilder: (_, state) => Scaffold(
    body: Center(child: Text('Ruta no encontrada: ${state.matchedLocation}')),
  ),
);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/router.dart';
import 'config/supabase_config.dart';
import 'providers/theme_provider.dart';
import 'services/background_sync_service.dart';
import 'services/ubicacion_service.dart';
import 'widgets/sync_banner.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey, // ignore: deprecated_member_use
  );

  await UbicacionService.init();

  runApp(const ProviderScope(child: GuiaTelefonicaApp()));
}

class GuiaTelefonicaApp extends ConsumerStatefulWidget {
  const GuiaTelefonicaApp({super.key});

  @override
  ConsumerState<GuiaTelefonicaApp> createState() => _GuiaTelefonicaAppState();
}

class _GuiaTelefonicaAppState extends ConsumerState<GuiaTelefonicaApp> {
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Deep links manejados por DeepLinkRouter
    // GoRouter maneja la navegación interna
    // DeepLinkRouter.handle se integra via GoRouter redirects cuando sea necesario
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Guía Telefónica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue, brightness: Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => SyncServiceListener(
        child: SyncBanner(child: child ?? const SizedBox()),
      ),
    );
  }
}

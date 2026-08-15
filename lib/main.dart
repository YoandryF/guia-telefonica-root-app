import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'providers/theme_provider.dart';
import 'services/deep_link_router.dart';
import 'services/ubicacion_service.dart';

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
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Link que abrió la app desde estado cerrado
    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) {
      // Esperar a que el árbol de widgets esté listo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _navigatorKey.currentContext;
        if (ctx != null) DeepLinkRouter.handle(initialLink, ctx);
      });
    }

    // Links mientras la app está en segundo plano o abierta
    _appLinks.uriLinkStream.listen((uri) {
      final ctx = _navigatorKey.currentContext;
      if (ctx != null) DeepLinkRouter.handle(uri, ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Guía Telefónica',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: themeMode,
      home: const SplashScreen(),
    );
  }
}

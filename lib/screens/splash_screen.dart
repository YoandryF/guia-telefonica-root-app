import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    // Esperar inicialización en paralelo (sin timer fijo)
    final prefs = await SharedPreferences.getInstance();
    final visto = prefs.getBool('onboarding_visto') ?? false;
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => visto ? const HomeScreen() : const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0284C7),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 120, height: 120, child: CustomPaint(painter: _LogoPainter())),
            const SizedBox(height: 24),
            const Text('Guía Telefónica', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('ROOT Ecosystem', style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
          ],
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final line = Paint()..color = Colors.white.withOpacity(0.4)..strokeWidth = 3;
    canvas.drawLine(Offset(w * 0.5, h * 0.25), Offset(w * 0.25, h * 0.55), line);
    canvas.drawLine(Offset(w * 0.5, h * 0.25), Offset(w * 0.75, h * 0.55), line);
    canvas.drawLine(Offset(w * 0.25, h * 0.55), Offset(w * 0.12, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.25, h * 0.55), Offset(w * 0.38, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.75, h * 0.55), Offset(w * 0.62, h * 0.82), line);
    canvas.drawLine(Offset(w * 0.75, h * 0.55), Offset(w * 0.88, h * 0.82), line);
    canvas.drawCircle(Offset(w * 0.5, h * 0.2), w * 0.12, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(w * 0.25, h * 0.55), w * 0.09, Paint()..color = const Color(0xFFBAE6FD));
    canvas.drawCircle(Offset(w * 0.75, h * 0.55), w * 0.09, Paint()..color = const Color(0xFFBAE6FD));
    canvas.drawCircle(Offset(w * 0.12, h * 0.82), w * 0.06, Paint()..color = const Color(0xFFE0F2FE));
    canvas.drawCircle(Offset(w * 0.38, h * 0.82), w * 0.06, Paint()..color = const Color(0xFFE0F2FE));
    canvas.drawCircle(Offset(w * 0.62, h * 0.82), w * 0.06, Paint()..color = const Color(0xFFE0F2FE));
    canvas.drawCircle(Offset(w * 0.88, h * 0.82), w * 0.06, Paint()..color = const Color(0xFFE0F2FE));
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

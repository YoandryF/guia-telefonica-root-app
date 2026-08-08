import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  final _pages = [
    {'icon': Icons.contacts, 'color': const Color(0xFF0284C7), 'title': 'Guía Telefónica', 'desc': 'Encuentra contactos verificados de tu comunidad. Funciona offline.'},
    {'icon': Icons.search, 'color': Colors.teal, 'title': 'Busca y filtra', 'desc': 'Busca por nombre, teléfono o CI. Filtra por categorías. Usa la voz.'},
    {'icon': Icons.security, 'color': Colors.orange, 'title': 'Reporta riesgos', 'desc': 'Si un contacto es fraudulento, repórtalo. La comunidad se protege.'},
    {'icon': Icons.sync, 'color': Colors.green, 'title': 'Siempre actualizado', 'desc': 'Se sincroniza automáticamente. Tus datos locales siempre disponibles.'},
  ];

  Future<void> _finalizar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_visto', true);
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(p['icon'] as IconData, size: 100, color: p['color'] as Color),
                        const SizedBox(height: 32),
                        Text(p['title'] as String, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        Text(p['desc'] as String, style: const TextStyle(fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => Container(
                margin: const EdgeInsets.all(4),
                width: _page == i ? 12 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _page == i ? const Color(0xFF0284C7) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(onPressed: () => _controller.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.ease), child: const Text('Anterior'))
                  else
                    const SizedBox(width: 80),
                  const Spacer(),
                  _page == _pages.length - 1
                      ? FilledButton(onPressed: _finalizar, child: const Text('Comenzar'))
                      : FilledButton(onPressed: () => _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.ease), child: const Text('Siguiente')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _finalizar, child: const Text('Saltar', style: TextStyle(color: Colors.grey))),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

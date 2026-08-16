import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/invitacion_service.dart';
import '../services/telegram_verification_service.dart';
import 'verificacion_telegram_screen.dart';

class InvitacionScreen extends StatefulWidget {
  const InvitacionScreen({super.key});

  @override
  State<InvitacionScreen> createState() => _InvitacionScreenState();
}

class _InvitacionScreenState extends State<InvitacionScreen> {
  String? _codigo;
  Map<String, dynamic> _resumen = {};
  bool _cargando = true;
  String? _telegramUserId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    // Obtener identidad Telegram del usuario
    final identity = await TelegramVerificationService.getIdentity();
    if (identity == null) {
      setState(() => _cargando = false);
      return;
    }

    _telegramUserId = identity.userId;

    final codigo = await InvitacionService.obtenerMiCodigo(_telegramUserId!);
    final resumen = await InvitacionService.getMisReferidos(_telegramUserId!);

    setState(() {
      _codigo = codigo;
      _resumen = resumen;
      _cargando = false;
    });
  }

  void _copiar() {
    if (_codigo == null) return;
    Clipboard.setData(ClipboardData(text: _codigo!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Código copiado')),
    );
  }

  void _compartir() {
    if (_codigo == null) return;
    // Link de Telegram: cuando el usuario lo toca, abre el bot con el código
    // El bot registra al referido y muestra la bienvenida + link a la app
    final linkTelegram = 'https://t.me/GuiaTelefonicaRootBot?start=invitacion_$_codigo';
    Share.share(
      '📱 Únete a la Guía Telefónica Colaborativa\n\n'
      'Usa mi código de invitación: $_codigo\n\n'
      '👇 Toca el link para unirte:\n$linkTelegram\n\n'
      'O descarga la app directamente:\n'
      'https://github.com/YoandryF/guia-telefonica-root-app/releases/latest',
      subject: 'Invitación a Guía Telefónica',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎁 Mis invitaciones'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _telegramUserId == null
              ? _SinVerificar()
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // ── Tarjeta del código ──────────────────────
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text(
                              '🎁 Tu código de invitación',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            if (_codigo != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _codigo!,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _copiar,
                                      icon: const Icon(Icons.copy, size: 18),
                                      label: const Text('Copiar'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: _compartir,
                                      icon: const Icon(Icons.share, size: 18),
                                      label: const Text('Compartir'),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              const Text('Error generando código', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Stats de referidos ──────────────────────
                    Row(
                      children: [
                        _StatBox(
                          valor: '${_resumen['total'] ?? 0}',
                          label: 'Referidos\ntotales',
                          color: Colors.blue,
                          icon: Icons.people,
                        ),
                        const SizedBox(width: 12),
                        _StatBox(
                          valor: '${(_resumen['referidos'] as List?)?.where((r) => r['activo'] == true).length ?? 0}',
                          label: 'Activos\nahora',
                          color: Colors.green,
                          icon: Icons.person_pin,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Lista de referidos ──────────────────────
                    if ((_resumen['total'] ?? 0) > 0) ...[
                      Text(
                        'Usuarios que se unieron con tu código',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...(_resumen['referidos'] as List? ?? []).map((r) {
                        final fecha = DateTime.tryParse(r['fecha']?.toString() ?? '');
                        final fechaStr = fecha != null
                            ? '${fecha.day}/${fecha.month}/${fecha.year}'
                            : '—';
                        final activo = r['activo'] == true;
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: activo
                                ? Colors.green.withOpacity(0.2)
                                : Colors.grey.withOpacity(0.2),
                            child: Icon(
                              Icons.person,
                              size: 16,
                              color: activo ? Colors.green : Colors.grey,
                            ),
                          ),
                          title: Text(
                            'Usuario referido',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text('Se unió el $fechaStr'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: activo
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              activo ? 'Activo' : 'Inactivo',
                              style: TextStyle(
                                fontSize: 11,
                                color: activo ? Colors.green : Colors.grey,
                              ),
                            ),
                          ),
                        );
                      }),
                    ] else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.person_add_disabled, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              const Text(
                                'Aún no tienes referidos.\nComparte tu código para invitar usuarios.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String valor;
  final String label;
  final Color color;
  final IconData icon;
  const _StatBox({required this.valor, required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _SinVerificar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          const Text(
            'Necesitas verificar tu cuenta de Telegram para acceder a las invitaciones.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              await mostrarVerificacionTelegram(context);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.send),
            label: const Text('Verificar con Telegram'),
          ),
        ],
      ),
    ),
  );
}
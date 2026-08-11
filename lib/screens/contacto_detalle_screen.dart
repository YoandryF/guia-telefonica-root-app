import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';
import '../services/supabase_service.dart';
import '../services/telegram_evidence_service.dart';
import 'verificacion_telegram_screen.dart';

class ContactoDetalleScreen extends StatefulWidget {
  final Contacto contacto;

  const ContactoDetalleScreen({super.key, required this.contacto});

  @override
  State<ContactoDetalleScreen> createState() => _ContactoDetalleScreenState();
}

class _ContactoDetalleScreenState extends State<ContactoDetalleScreen> {
  final _localDb = LocalDatabaseService();
  bool _esFavorito = false;
  int _reportes = 0;
  bool _esVerificado = false;
  String? _nota;

  @override
  void initState() {
    super.initState();
    _verificarFavorito();
    _cargarReportes();
    _cargarNota();
    _localDb.registrarAcceso(widget.contacto.id);
  }

  Future<void> _verificarFavorito() async {
    final fav = await _localDb.esFavorito(widget.contacto.id);
    setState(() => _esFavorito = fav);
  }

  Future<void> _cargarReportes() async {
    try {
      final info = await SupabaseService().getInfoReportes(widget.contacto.id);
      setState(() {
        _reportes = (info['pendientes'] as int) + (info['aprobados'] as int);
        _esVerificado = info['esVerificado'] as bool;
      });
    } catch (_) {}
  }

  Future<void> _cargarNota() async {
    final nota = await _localDb.getNota(widget.contacto.id);
    setState(() => _nota = nota);
  }

  Future<void> _editarNota() async {
    final controller = TextEditingController(text: _nota ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📝 Nota privada'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Ej: Cobra caro, pero trabaja bien...'),
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          if (_nota != null)
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (result == null) return;
    await _localDb.guardarNota(widget.contacto.id, result);
    _cargarNota();
  }

  Future<void> _toggleFavorito() async {
    if (_esFavorito) {
      await _localDb.eliminarFavorito(widget.contacto.id);
    } else {
      await _localDb.agregarFavorito(widget.contacto.id);
    }
    setState(() => _esFavorito = !_esFavorito);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_esFavorito ? '⭐ Agregado a favoritos' : 'Eliminado de favoritos')),
      );
    }
  }

  Future<void> _llamar() async {
    final uri = Uri.parse('tel:${widget.contacto.telefono}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _enviarSms() async {
    final uri = Uri.parse('smsto:${widget.contacto.telefono}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _abrirWhatsApp() async {
    final numero = widget.contacto.telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    final completo = numero.startsWith('+') ? numero : '+53$numero';
    final uri = Uri.parse('https://wa.me/${completo.replaceAll('+', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _verEnMapa() async {
    final c = widget.contacto;
    // Construir query con ubicación completa
    final partes = <String>[];
    if (c.direccion != null) partes.add(c.direccion!);
    if (c.municipio != null) partes.add(c.municipio!);
    if (c.provincia != null) partes.add(c.provincia!);
    if (partes.isEmpty) return;
    final query = Uri.encodeComponent(partes.join(', '));
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copiar(String texto, String label) {
    Clipboard.setData(ClipboardData(text: texto));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('📋 $label copiado'), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _compartir() async {
    final c = widget.contacto;
    String texto = '📋 Contacto de Guía Telefónica:\n'
        '👤 ${c.nombreCompleto}\n'
        '📱 ${c.telefono}\n';
    if (c.ubicacionCompleta != null) texto += '📍 ${c.ubicacionCompleta}\n';
    if (c.direccion != null) texto += '🏠 ${c.direccion}\n';
    if (c.ci != null) texto += '🆔 CI: ${c.ci}\n';
    if (c.categoriaNombre != null) texto += '📂 ${c.categoriaNombre}\n';

    await Share.share(texto, subject: 'Contacto: ${c.nombreCompleto}');
  }

  Future<void> _guardarEnAgenda() async {
    final c = widget.contacto;
    try {
      final intent = Uri.parse('intent://contacts#Intent;action=android.intent.action.INSERT;type=vnd.android.cursor.dir/contact;S.name=${Uri.encodeComponent(c.nombreCompleto)};S.phone=${Uri.encodeComponent(c.telefono)};end');
      if (await canLaunchUrl(intent)) {
        await launchUrl(intent);
        return;
      }
    } catch (_) {}

    final datos = '${c.nombreCompleto}\n${c.telefono}${c.direccion != null ? '\n${c.direccion}' : ''}';
    Clipboard.setData(ClipboardData(text: datos));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📋 Datos copiados — pega en tu app de Contactos')),
      );
    }
  }

  void _mostrarQR() {
    final c = widget.contacto;
    final vcard = 'BEGIN:VCARD\n'
        'VERSION:3.0\n'
        'N:${c.apellido};${c.nombre}\n'
        'FN:${c.nombreCompleto}\n'
        'TEL:${c.telefono}\n'
        '${c.direccion != null ? 'ADR:;;${c.direccion};;;${c.municipio ?? ''};\n' : ''}'
        'END:VCARD';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.nombreCompleto, textAlign: TextAlign.center),
        content: SizedBox(
          width: 250,
          height: 280,
          child: Column(
            children: [
              QrImageView(
                data: vcard,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 8),
              Text('Escanea para guardar contacto',
                  style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _avalar() async {
    // Requiere verificación Telegram
    final identity = await requiereVerificacion(context);
    if (identity == null) return;

    final result = await SupabaseService().avalarContacto(
      widget.contacto.id,
      telegramUserId: identity.userId,
    );
    if (!mounted) return;
    if (result['error'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('👍 Aval registrado. Gracias.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⚠️ ${result['error']}')));
    }
  }

  Future<void> _reclamar() async {
    // Requiere verificación Telegram
    final identity = await requiereVerificacion(context);
    if (identity == null) return;

    final ctrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚖️ Reclamar'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Si eres el dueño de este número o conoces al contacto, explica por qué el reporte es injusto.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Tu mensaje...', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Enviar')),
        ],
      ),
    );
    if (msg == null || msg.isEmpty) return;
    final result = await SupabaseService().reclamarContacto(
      widget.contacto.id, msg,
      reclamanteId: identity.userId,
    );
    if (!mounted) return;
    if (result['error'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚖️ Reclamo enviado. Un admin lo revisará.')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ${result['error']}')));
    }
  }


  Future<void> _reportar() async {
    // Requiere verificación Telegram
    final identity = await requiereVerificacion(context);
    if (identity == null) return; // Canceló o no verificó

    final motivos = [
      {'value': 'numero_incorrecto', 'label': '📞 Número incorrecto'},
      {'value': 'no_existe', 'label': '❌ Ya no existe'},
      {'value': 'spam', 'label': '📢 Spam / Acoso'},
      {'value': 'duplicado', 'label': '🔄 Duplicado'},
      {'value': 'otro', 'label': '📋 Otro'},
    ];

    String? motivoSeleccionado;
    final descripcionCtrl = TextEditingController();
    File? evidencia;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('⚠️ Reportar contacto'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...motivos.map((m) => RadioListTile<String>(
                  title: Text(m['label']!, style: const TextStyle(fontSize: 14)),
                  value: m['value']!,
                  groupValue: motivoSeleccionado,
                  onChanged: (v) => setDialogState(() => motivoSeleccionado = v),
                  dense: true,
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: descripcionCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),

                // Botón de evidencia
                if (evidencia == null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final source = await showModalBottomSheet<ImageSource>(
                        context: ctx,
                        builder: (bCtx) => SafeArea(
                          child: Wrap(children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt),
                              title: const Text('Cámara'),
                              onTap: () => Navigator.pop(bCtx, ImageSource.camera),
                            ),
                            ListTile(
                              leading: const Icon(Icons.photo_library),
                              title: const Text('Galería'),
                              onTap: () => Navigator.pop(bCtx, ImageSource.gallery),
                            ),
                          ]),
                        ),
                      );
                      if (source == null) return;
                      final svc = TelegramEvidenceService();
                      final file = await svc.pickImage(source: source);
                      if (file != null) {
                        setDialogState(() => evidencia = file);
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Adjuntar evidencia'),
                  )
                else
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(evidencia!, height: 120, width: double.infinity, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () => setDialogState(() => evidencia = null),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Quitar', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: motivoSeleccionado == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Reportar'),
            ),
          ],
        ),
      ),
    );

    if (result != true || motivoSeleccionado == null) return;

    // Enviar evidencia a Telegram si hay
    int? evidenciaMsgId;
    if (evidencia != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📤 Subiendo evidencia...')),
        );
      }
      final evSvc = TelegramEvidenceService();
      final evResult = await evSvc.enviarEvidencia(
        imagen: evidencia!,
        contactoNombre: '${widget.contacto.nombre} ${widget.contacto.apellido}',
        contactoTelefono: widget.contacto.telefono,
        motivo: motivoSeleccionado!,
        reportadorUsername: identity.username ?? identity.userId,
      );
      if (evResult.success) {
        evidenciaMsgId = evResult.messageId;
      }
    }

    final resp = await SupabaseService().reportarContacto(
      contactoId: widget.contacto.id,
      motivo: motivoSeleccionado!,
      descripcion: descripcionCtrl.text.isNotEmpty ? descripcionCtrl.text : null,
      telegramUserId: identity.userId,
      evidenciaMsgId: evidenciaMsgId,
    );

    if (mounted) {
      if (resp['error'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Reporte enviado. Gracias por informar.')),
        );
        _cargarReportes();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${resp['error']}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contacto;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Cabecera
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.primary,
                    child: Hero(
                      tag: 'avatar_${c.id}',
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(
                          c.nombre[0].toUpperCase(),
                          style: const TextStyle(fontSize: 32, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(c.nombreCompleto, style: theme.textTheme.headlineSmall),
                  if (c.ubicacionCompleta != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(c.ubicacionCompleta!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                        ],
                      ),
                    ),
                  if (c.categoriaNombre != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Chip(
                        avatar: Text(c.categoriaIcono ?? '📂'),
                        label: Text(c.categoriaNombre!),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Badge de reportes
            if (_esVerificado || _reportes >= 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _esVerificado
                                  ? 'Contacto verificado como riesgoso'
                                  : 'Este contacto ha sido reportado $_reportes veces',
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _avalar,
                            icon: const Icon(Icons.thumb_up, size: 16, color: Colors.green),
                            label: const Text('Es legítimo', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _reclamar,
                            icon: const Icon(Icons.gavel, size: 16, color: Colors.blue),
                            label: const Text('Reclamar', style: TextStyle(fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Teléfono
            _SeccionDato(
              icono: Icons.phone,
              label: 'Teléfono',
              valor: c.telefono,
              acciones: [
                _AccionBtn(icon: Icons.call, label: 'Llamar', color: Colors.green, onTap: _llamar),
                _AccionBtn(icon: Icons.sms, label: 'SMS', color: Colors.blue, onTap: _enviarSms),
                _AccionBtn(icon: Icons.chat, label: 'WhatsApp', color: const Color(0xFF25D366), onTap: _abrirWhatsApp),
                _AccionBtn(icon: Icons.copy, label: 'Copiar', onTap: () => _copiar(c.telefono, 'Teléfono')),
              ],
            ),

            // Ubicación
            if (c.provincia != null || c.municipio != null)
              _SeccionDato(
                icono: Icons.map,
                label: 'Ubicación',
                valor: c.ubicacionCompleta ?? '',
                acciones: [
                  _AccionBtn(icon: Icons.map, label: 'Mapa', color: Colors.red, onTap: _verEnMapa),
                ],
              ),

            // Dirección
            if (c.direccion != null)
              _SeccionDato(
                icono: Icons.location_on,
                label: 'Dirección',
                valor: c.direccion!,
                acciones: [
                  _AccionBtn(icon: Icons.map, label: 'Mapa', color: Colors.red, onTap: _verEnMapa),
                  _AccionBtn(icon: Icons.copy, label: 'Copiar', onTap: () => _copiar(c.direccion!, 'Dirección')),
                ],
              ),

            // CI
            if (c.ci != null)
              _SeccionDato(
                icono: Icons.badge,
                label: 'Carnet de Identidad',
                valor: c.ci!,
                acciones: [
                  _AccionBtn(icon: Icons.copy, label: 'Copiar', onTap: () => _copiar(c.ci!, 'CI')),
                ],
              ),

            const SizedBox(height: 24),

            // Acciones generales
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CircleAction(
                    icon: Icons.share,
                    color: theme.colorScheme.primary,
                    onTap: _compartir,
                  ),
                  _CircleAction(
                    icon: Icons.person_add,
                    color: Colors.teal,
                    onTap: _guardarEnAgenda,
                  ),
                  _CircleAction(
                    icon: Icons.star,
                    color: _esFavorito ? Colors.amber : Colors.grey,
                    filled: _esFavorito,
                    onTap: _toggleFavorito,
                  ),
                  _CircleAction(
                    icon: Icons.qr_code,
                    color: Colors.deepPurple,
                    onTap: _mostrarQR,
                  ),
                  _CircleAction(
                    icon: Icons.warning_amber,
                    color: Colors.red,
                    onTap: _reportar,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Nota privada
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _editarNota,
                child: Card(
                  color: _nota != null ? Colors.amber.withOpacity(0.1) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.sticky_note_2, size: 20, color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _nota ?? 'Agregar nota privada...',
                            style: TextStyle(
                              fontSize: 13,
                              color: _nota != null ? null : Colors.grey,
                              fontStyle: _nota != null ? FontStyle.normal : FontStyle.italic,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.edit, size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Info de registro
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('Información', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (c.fechaCreacion != null)
                        Text('📅 Registrado: ${_formatFecha(c.fechaCreacion!)}',
                            style: theme.textTheme.bodySmall),
                      if (c.fechaAprobacion != null)
                        Text('✅ Aprobado: ${_formatFecha(c.fechaAprobacion!)}',
                            style: theme.textTheme.bodySmall),
                      if (c.creadoDesde != null)
                        Text('📱 Desde: ${c.creadoDesde}',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatFecha(DateTime fecha) {
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }
}

class _SeccionDato extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  final List<_AccionBtn> acciones;

  const _SeccionDato({
    required this.icono,
    required this.label,
    required this.valor,
    required this.acciones,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(valor, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: acciones,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _AccionBtn({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _CircleAction({
    required this.icon,
    required this.color,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/contacto.dart';
import '../services/local_database_service.dart';

class ContactoDetalleScreen extends StatefulWidget {
  final Contacto contacto;

  const ContactoDetalleScreen({super.key, required this.contacto});

  @override
  State<ContactoDetalleScreen> createState() => _ContactoDetalleScreenState();
}

class _ContactoDetalleScreenState extends State<ContactoDetalleScreen> {
  final _localDb = LocalDatabaseService();
  bool _esFavorito = false;

  @override
  void initState() {
    super.initState();
    _verificarFavorito();
  }

  Future<void> _verificarFavorito() async {
    final fav = await _localDb.esFavorito(widget.contacto.id);
    setState(() => _esFavorito = fav);
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
    final uri = Uri.parse('sms:${widget.contacto.telefono}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _abrirWhatsApp() async {
    // Limpiar número (quitar guiones, espacios)
    final numero = widget.contacto.telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    // Si no tiene código de país, asumir Cuba (+53)
    final completo = numero.startsWith('+') ? numero : '+53$numero';
    final uri = Uri.parse('https://wa.me/${completo.replaceAll('+', '')}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _verEnMapa() async {
    if (widget.contacto.direccion == null) return;
    final query = Uri.encodeComponent(widget.contacto.direccion!);
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
    if (c.direccion != null) texto += '📍 ${c.direccion}\n';
    if (c.ci != null) texto += '🆔 CI: ${c.ci}\n';
    if (c.categoriaNombre != null) texto += '📂 ${c.categoriaNombre}\n';

    await Share.share(texto, subject: 'Contacto: ${c.nombreCompleto}');
  }

  Future<void> _guardarEnAgenda() async {
    final c = widget.contacto;
    // Intent para crear contacto en la agenda nativa
    final uri = Uri(
      scheme: 'content',
      host: 'com.android.contacts',
      path: '/contacts',
    );

    // Usar intent directo de Android para agregar contacto
    final addContactUri = Uri.parse(
      'content://com.android.contacts/contacts#Intent;'
      'action=android.intent.action.INSERT;'
      'type=vnd.android.cursor.dir/contact;'
      'S.name=${c.nombreCompleto};'
      'S.phone=${c.telefono};'
      'end',
    );

    // Método más compatible: abrir con ACTION_INSERT
    final contactUri = Uri.parse(
      'https://contacts.google.com/new?name=${Uri.encodeComponent(c.nombreCompleto)}&phone=${Uri.encodeComponent(c.telefono)}',
    );

    // Intentar con el método de intent de Android
    try {
      final intent = Uri.parse('intent://contacts#Intent;action=android.intent.action.INSERT;type=vnd.android.cursor.dir/contact;S.name=${Uri.encodeComponent(c.nombreCompleto)};S.phone=${Uri.encodeComponent(c.telefono)};end');
      if (await canLaunchUrl(intent)) {
        await launchUrl(intent);
        return;
      }
    } catch (_) {}

    // Fallback: copiar datos y notificar
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
        '${c.direccion != null ? 'ADR:;;${c.direccion}\n' : ''}'
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

  @override
  Widget build(BuildContext context) {
    final c = widget.contacto;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        actions: [
          IconButton(
            icon: Icon(_esFavorito ? Icons.star : Icons.star_border,
                color: _esFavorito ? Colors.amber : null),
            onPressed: _toggleFavorito,
            tooltip: _esFavorito ? 'Quitar de favoritos' : 'Agregar a favoritos',
          ),
        ],
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
                    child: Text(
                      c.nombre[0].toUpperCase(),
                      style: const TextStyle(fontSize: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(c.nombreCompleto, style: theme.textTheme.headlineSmall),
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
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _compartir,
                      icon: const Icon(Icons.share),
                      label: const Text('Compartir'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _guardarEnAgenda,
                      icon: const Icon(Icons.contacts),
                      label: const Text('Agenda'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _mostrarQR,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('QR'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Info de registro
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../services/background_sync_service.dart';

/// Banner persistente que aparece en la parte inferior de TODAS las pantallas
/// mientras hay una sincronización en progreso o recién terminada.
/// Se integra en el MaterialApp como overlay.
class SyncBanner extends ConsumerWidget {
  final Widget child;
  const SyncBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);

    // No mostrar nada en estado idle
    if (sync.estado == SyncEstado.idle) return child;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BannerContent(sync: sync),
        ),
      ],
    );
  }
}

class _BannerContent extends ConsumerWidget {
  final SyncState sync;
  const _BannerContent({required this.sync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme   = Theme.of(context).colorScheme;
    final enProgreso = sync.enProgreso;

    // Color del banner según estado
    final bgColor = switch (sync.estado) {
      SyncEstado.completado => Colors.green.shade700,
      SyncEstado.error      => Colors.red.shade700,
      SyncEstado.cancelado  => Colors.orange.shade700,
      _                     => scheme.primary,
    };

    return Material(
      elevation: 8,
      child: Container(
        color: bgColor,
        padding: EdgeInsets.only(
          left: 16,
          right: 8,
          top: 10,
          bottom: MediaQuery.of(context).padding.bottom + 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icono animado o estático según estado
                if (enProgreso)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(
                    switch (sync.estado) {
                      SyncEstado.completado => Icons.check_circle,
                      SyncEstado.error      => Icons.error,
                      SyncEstado.cancelado  => Icons.cancel,
                      _                     => Icons.sync,
                    },
                    color: Colors.white,
                    size: 16,
                  ),
                const SizedBox(width: 10),

                // Mensaje
                Expanded(
                  child: Text(
                    sync.mensajeProgreso,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Botón cancelar (solo durante progreso)
                if (enProgreso)
                  TextButton(
                    onPressed: () async {
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancelar sincronización'),
                          content: const Text(
                            '¿Seguro que quieres cancelar?\n'
                            'Los contactos descargados hasta ahora se conservarán.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Continuar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Cancelar sync'),
                            ),
                          ],
                        ),
                      );
                      if (confirmar == true) {
                        BackgroundSyncService.cancelarSync();
                      }
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                  )
                // Botón cerrar (en estados finales)
                else
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ref.read(syncProvider.notifier).reset(),
                  ),
              ],
            ),

            // Barra de progreso (solo durante descarga)
            if (sync.estado == SyncEstado.descargando && sync.total > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: sync.progreso,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  minHeight: 3,
                ),
              ),
            ] else if (enProgreso) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  minHeight: 3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

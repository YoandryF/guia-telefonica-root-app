import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/sync_provider.dart';
import '../services/background_sync_service.dart';

/// Banner persistente en la parte inferior de TODAS las pantallas.
/// Usa builder en MaterialApp — sobrevive a cualquier navegación.
/// ExcludeFocus evita que el banner robe el foco y bloquee botones de hardware.
class SyncBanner extends ConsumerWidget {
  final Widget child;
  const SyncBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);

    if (sync.estado == SyncEstado.idle) return child;

    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // ExcludeFocus: el banner NUNCA roba el foco del árbol principal
          // Esto previene que bloquee botones de hardware (volumen, back, etc.)
          child: ExcludeFocus(
            child: _BannerContent(sync: sync),
          ),
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
    final scheme     = Theme.of(context).colorScheme;
    final enProgreso = sync.enProgreso;

    final bgColor = switch (sync.estado) {
      SyncEstado.completado => Colors.green.shade700,
      SyncEstado.error      => Colors.red.shade700,
      SyncEstado.cancelado  => Colors.orange.shade700,
      _                     => scheme.primary,
    };

    return Material(
      elevation: 8,
      // color transparent para que Material no intercepte eventos fuera del área visible
      color: Colors.transparent,
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
                if (enProgreso)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
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
                    color: Colors.white, size: 16,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sync.mensajeProgreso,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
                // Error con offset guardado → botón Continuar
                else if (sync.puedeContinuar)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          final offset = sync.offsetGuardado;
                          ref.read(syncProvider.notifier).reset();
                          BackgroundSyncService.iniciarSync(ref, desdeOffset: offset);
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        child: const Text('Continuar', style: TextStyle(fontSize: 12)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => ref.read(syncProvider.notifier).reset(),
                      ),
                    ],
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ref.read(syncProvider.notifier).reset(),
                  ),
              ],
            ),
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

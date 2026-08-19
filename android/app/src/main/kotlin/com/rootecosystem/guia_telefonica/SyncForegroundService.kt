package com.rootecosystem.guia_telefonica

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * ForegroundService nativo para sincronización en background.
 * Se comunica con Flutter via EventChannel (progreso) y MethodChannel (control).
 *
 * Flujo:
 * 1. Flutter llama MainActivity.startSyncService()
 * 2. MainActivity inicia este servicio con startForegroundService()
 * 3. El servicio envía datos de progreso via SyncEventSink
 * 4. Flutter puede cancelar llamando stopSyncService()
 */
class SyncForegroundService : Service() {

    companion object {
        const val CHANNEL_ID          = "guia_sync_channel"
        const val NOTIFICATION_ID     = 888
        const val ACTION_STOP         = "com.rootecosystem.guia_telefonica.STOP_SYNC"

        // Sink estático para enviar progreso a Flutter
        // Se asigna desde MainActivity cuando Flutter registra el EventChannel
        var eventSink: EventChannel.EventSink? = null

        // Flag de cancelación — Flutter lo activa, el Dart Isolate lo lee
        @Volatile
        var cancelRequested: Boolean = false

        fun sendProgress(estado: String, descargados: Int, total: Int, error: String? = null) {
            val data = mutableMapOf<String, Any>(
                "estado"      to estado,
                "descargados" to descargados,
                "total"       to total,
            )
            if (error != null) data["error"] = error
            // Debe correr en el main thread para EventChannel
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(data)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        crearNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                cancelRequested = true
                stopSelf()
                return START_NOT_STICKY
            }
            "UPDATE_NOTIFICATION" -> {
                val texto = intent.getStringExtra("texto") ?: "Sincronizando..."
                actualizarNotificacion(texto)
                return START_NOT_STICKY
            }
        }

        cancelRequested = false
        startForeground(NOTIFICATION_ID, buildNotification("Sincronizando contactos..."))
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        // Notificar a Flutter que el servicio terminó
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.endOfStream()
        }
    }

    fun actualizarNotificacion(texto: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(texto))
    }

    private fun buildNotification(texto: String): Notification {
        val stopIntent = Intent(this, SyncForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Intent para abrir la app al tocar la notificación
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPending = PendingIntent.getActivity(
            this, 1, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Guía Telefónica — Sincronizando")
            .setContentText(texto)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_delete, "Cancelar", stopPending)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun crearNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sincronización Guía Telefónica",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Progreso de sincronización de contactos"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}

package org.simplerunning.simplerunning

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.ResultReceiver

// Keeps the existing BLE connection and Dart sampling timers alive while the
// activity is backgrounded. It never starts or resumes a workout on its own.
class RecordingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val reply = intent?.getParcelableExtra<ResultReceiver>("reply")
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(
                    "recording", "Conexión con la cinta", NotificationManager.IMPORTANCE_LOW
                ))
            }
            val openApp = PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java).apply {
                    this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, "recording")
            } else {
                Notification.Builder(this).setPriority(Notification.PRIORITY_LOW)
            }
            val notification = builder
                .setSmallIcon(R.drawable.ic_running)
                .setContentTitle("SimpleRunning · cinta conectada")
                .setContentText("Puedes bloquear la pantalla. Toca para volver al entrenamiento.")
                .setContentIntent(openApp)
                .setCategory(Notification.CATEGORY_SERVICE)
                .setOngoing(true)
                .setShowWhen(false)
                .build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(1001, notification)
            }
            if (wakeLock == null) {
                wakeLock = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SimpleRunning:recording")
                    .apply {
                        setReferenceCounted(false)
                        // Owned by this service; released on disconnect, finish,
                        // activity destruction or task removal, without a workout time limit.
                        acquire()
                    }
            }
            reply?.send(0, null)
        } catch (error: RuntimeException) {
            releaseResources()
            stopSelf()
            reply?.send(1, Bundle().apply { putString("error", error.message) })
        }
        return START_NOT_STICKY
    }

    private fun releaseResources() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        releaseResources()
        super.onDestroy()
    }
}

package dev.opencodeapk.runtime

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app process alive while the OpenCode server runs. It holds no logic: [RuntimeHost] owns the server,
 * this only shows the required notification (with a Stop action) and forwards memory-pressure callbacks.
 * Started by the host while the app is in the foreground; stopped by the host when the server stops or fails.
 */
class RuntimeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            RuntimeHost.get(this).stopServerAsync("user")
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY // never resurrect a server nobody asked for
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        RuntimeHost.get(this).onTrimMemory(level)
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "OpenCode server", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while the OpenCode server runs on this device"
                setShowBadge(false)
            },
        )
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = packageManager.getLaunchIntentForPackage(packageName)
            ?.let { PendingIntent.getActivity(this, 0, it, flags) }
        val stop = PendingIntent.getService(
            this, 1, Intent(this, RuntimeService::class.java).setAction(ACTION_STOP), flags,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("OpenCode is running")
            .setContentText("Private Linux sandbox on this device")
            .setContentIntent(open)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    companion object {
        const val ACTION_STOP = "dev.opencodeapk.runtime.STOP"
        private const val CHANNEL_ID = "runtime"
        private const val NOTIFICATION_ID = 1
    }
}

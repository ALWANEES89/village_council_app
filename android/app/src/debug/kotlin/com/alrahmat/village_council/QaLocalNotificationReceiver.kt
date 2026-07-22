package com.alrahmat.village_council

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Debug-only local notification hook for visual OMR QA.
 *
 * This source set and its manifest receiver are excluded from release builds.
 * It deliberately accepts only deterministic fake amounts and performs no
 * Firebase or network access.
 */
class QaLocalNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val amountBaisa = intent.getIntExtra(EXTRA_AMOUNT_BAISA, -1)
        if (amountBaisa !in ALLOWED_AMOUNTS) return

        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "OMR local QA",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Debug-only local currency display verification"
                },
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val formattedAmount = formatOmaniRial(amountBaisa)
        manager.notify(
            NOTIFICATION_ID_BASE + amountBaisa,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("اختبار محلي لعرض الريال")
                .setContentText("القيمة: $formattedAmount ر.ع.")
                .setStyle(
                    Notification.BigTextStyle()
                        .bigText("القيمة: $formattedAmount ر.ع. — إشعار QA محلي فقط"),
                )
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun formatOmaniRial(amountBaisa: Int): String {
        val rials = amountBaisa / 1000
        val fraction = (amountBaisa % 1000).toString().padStart(3, '0')
        return "$rials.$fraction"
    }

    companion object {
        const val ACTION = "com.alrahmat.village_council.QA_OMR_NOTIFICATION"
        const val EXTRA_AMOUNT_BAISA = "amountBaisa"
        private const val CHANNEL_ID = "qa_omr_local_debug"
        private const val NOTIFICATION_ID_BASE = 920000
        private val ALLOWED_AMOUNTS = setOf(5000, 7500, 8000, 12500)
    }
}

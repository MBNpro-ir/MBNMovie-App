package com.mbn.movie

import android.app.PendingIntent
import android.app.ActivityOptions
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/** Receives only explicit PackageInstaller callbacks; it is not exported. */
class UpdateInstallReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DeviceBridge.installStatusAction) return
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmation = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                }
                if (confirmation == null) {
                    DeviceBridge.publishInstallStatus("failed")
                } else {
                    context.startActivity(
                        confirmation.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                val launch = context.packageManager
                    .getLaunchIntentForPackage(context.packageName)
                    ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                if (launch != null) {
                    val launchMode = if (Build.VERSION.SDK_INT >= 36) {
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS
                    } else {
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    }
                    val creatorOptions = if (Build.VERSION.SDK_INT >= 35) {
                        ActivityOptions.makeBasic().apply {
                            pendingIntentCreatorBackgroundActivityStartMode = launchMode
                        }.toBundle()
                    } else {
                        null
                    }
                    val pending = PendingIntent.getActivity(
                        context,
                        0,
                        launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                        creatorOptions,
                    )
                    try {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val senderOptions = ActivityOptions.makeBasic().apply {
                                pendingIntentBackgroundActivityStartMode = launchMode
                            }.toBundle()
                            pending.send(
                                context,
                                0,
                                null,
                                null,
                                null,
                                null,
                                senderOptions,
                            )
                        } else {
                            pending.send()
                        }
                    } catch (_: PendingIntent.CanceledException) { }
                }
            }
            else -> DeviceBridge.publishInstallStatus("failed")
        }
    }
}

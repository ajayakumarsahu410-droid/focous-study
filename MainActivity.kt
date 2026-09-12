package com.focusstudy.app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.focusstudy.app/focus_mode"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                when (call.method) {

                    // Has the user granted "Do Not Disturb access" to us?
                    "isDndAccessGranted" -> {
                        val granted =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                                nm.isNotificationPolicyAccessGranted
                            else true
                        result.success(granted)
                    }

                    // Deep-link the user into Settings > Special access > DND access
                    "openDndSettings" -> {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }

                    // Read the current filter so we can restore it later
                    "getInterruptionFilter" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(nm.currentInterruptionFilter)
                        } else {
                            result.success(NotificationManager.INTERRUPTION_FILTER_ALL)
                        }
                    }

                    /*
                     * filter values:
                     *  1 = INTERRUPTION_FILTER_ALL      (normal / DND off)
                     *  2 = INTERRUPTION_FILTER_PRIORITY (priority only)
                     *  3 = INTERRUPTION_FILTER_NONE     (total silence)
                     *  4 = INTERRUPTION_FILTER_ALARMS   (alarms only  <-- best for study)
                     */
                    "setInterruptionFilter" -> {
                        val filter = call.argument<Int>("filter") ?: 1
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!nm.isNotificationPolicyAccessGranted) {
                                result.error(
                                    "NO_DND_ACCESS",
                                    "ACCESS_NOTIFICATION_POLICY has not been granted by the user.",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                            nm.setInterruptionFilter(filter)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}

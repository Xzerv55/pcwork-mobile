package com.pcworkbg.pcwork_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationChannel = "com.pcworkbg.pcwork_mobile/notifications"
    private val notificationRequestCode = 7301
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "requestNotificationPermission") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < 33) {
                    result.success(true)
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                    return@setMethodCallHandler
                }
                val preferences = getSharedPreferences("pcwork_notification_permissions", MODE_PRIVATE)
                if (preferences.getBoolean("first_prompt_requested", false)) {
                    // Android may no longer show the system dialog after a denial.
                    // The app's notification settings action remains available.
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (pendingNotificationResult != null) {
                    result.error("permission_in_progress", "Notification permission request is already running.", null)
                    return@setMethodCallHandler
                }
                preferences.edit().putBoolean("first_prompt_requested", true).apply()
                pendingNotificationResult = result
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    notificationRequestCode
                )
            }
    }

    @Deprecated("Deprecated in Android API; required for FlutterActivity permission result forwarding")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationRequestCode) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
    }
}

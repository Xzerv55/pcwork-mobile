package com.pcworkbg.pcwork_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import java.io.File
import androidx.core.content.FileProvider
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationChannel = "com.pcworkbg.pcwork_mobile/notifications"
    private val notificationRequestCode = 7301
    private val callRequestCode = 7302
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingCallResult: MethodChannel.Result? = null
    private var pendingCallNumber: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pcworkbg.pcwork_mobile/updater")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) { result.error("invalid_path", "APK path is missing.", null); return@setMethodCallHandler }
                try {
                    val apk = File(path)
                    if (!apk.isFile || apk.length() <= 0L || apk.extension.lowercase() != "apk") {
                        result.error("invalid_apk", "Downloaded APK file is invalid.", null); return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                        val settingsIntent = Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                            data = android.net.Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.error("install_permission_required", "Разреши инсталиране от PCWork, след което натисни отново „Актуализирай сега“.", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("installer_error", e.message ?: "Could not open Android installer.", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.pcworkbg.pcwork_mobile/phone")
            .setMethodCallHandler { call, result ->
                if (call.method != "callPhone") { result.notImplemented(); return@setMethodCallHandler }
                val number = call.argument<String>("number")?.trim().orEmpty()
                if (number.isBlank()) { result.error("invalid_number", "Phone number is missing.", null); return@setMethodCallHandler }
                if (checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
                    try {
                        startActivity(Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:$number")))
                        result.success(true)
                    } catch (e: Exception) { result.error("call_failed", e.message ?: "Could not start call.", null) }
                } else {
                    if (pendingCallResult != null) { result.error("permission_in_progress", "Phone permission request is already running.", null); return@setMethodCallHandler }
                    pendingCallResult = result
                    pendingCallNumber = number
                    requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), callRequestCode)
                }
            }
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
        } else if (requestCode == callRequestCode) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            val result = pendingCallResult
            val number = pendingCallNumber
            pendingCallResult = null
            pendingCallNumber = null
            if (granted && !number.isNullOrBlank()) {
                try { startActivity(Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:$number"))); result?.success(true) }
                catch (e: Exception) { result?.error("call_failed", e.message ?: "Could not start call.", null) }
            } else result?.success(false)
        }
    }
}

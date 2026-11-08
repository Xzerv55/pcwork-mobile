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
    private var pendingNotificationResult: MethodChannel.Result? = null

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
                if (call.method != "openDialer") { result.notImplemented(); return@setMethodCallHandler }
                val number = call.argument<String>("number")?.trim()
                if (number.isNullOrBlank()) { result.error("invalid_number", "Phone number is missing.", null); return@setMethodCallHandler }
                try {
                    val intent = Intent(Intent.ACTION_DIAL, android.net.Uri.parse("tel:" + android.net.Uri.encode(number)))
                    val preferredDialers = listOf("com.google.android.dialer", "com.samsung.android.dialer", "com.android.phone", "com.android.dialer", "com.miui.dialer", "com.oneplus.dialer")
                    val dialerPackage = preferredDialers.firstOrNull { packageManager.getLaunchIntentForPackage(it) != null }
                    if (dialerPackage == null) {
                        result.error("dialer_unavailable", "No supported phone dialer is installed.", null)
                    } else {
                        intent.setPackage(dialerPackage)
                        startActivity(intent)
                        result.success(true)
                    }
                } catch (e: Exception) {
                    result.error("dialer_error", e.message ?: "Could not open phone dialer.", null)
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
        }
    }
}

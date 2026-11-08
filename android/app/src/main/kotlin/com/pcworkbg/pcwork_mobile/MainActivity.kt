package com.pcworkbg.pcwork_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.content.Intent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import org.json.JSONObject
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
    private var notificationMethodChannel: MethodChannel? = null
    private var pendingNotificationData: Map<String, Any>? = null

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
        notificationMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationChannel)
        notificationMethodChannel?.setMethodCallHandler { call, result ->
                if (call.method == "showLocalNotification") {
                    try {
                        val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: "PCWork"
                        val body = call.argument<String>("body") ?: "Имате ново известие от PCWork."
                        val data = call.argument<Map<String, Any>>("data") ?: emptyMap()
                        showPcworkNotification(title, body, data)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("notification_error", e.message ?: "Could not show notification.", null)
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "getPendingNotification") {
                    val data = pendingNotificationData ?: readNotificationIntent(intent)
                    pendingNotificationData = null
                    intent?.removeExtra("pcwork_notification_data")
                    result.success(data)
                    return@setMethodCallHandler
                }
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

    private fun showPcworkNotification(title: String, body: String, data: Map<String, Any>) {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val channelId = "pcwork_transactional_updates"
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "PCWork известия", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Поръчки и сервизни заявки от PCWork"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
        val json = JSONObject()
        data.forEach { (key, value) -> json.put(key, value) }
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("pcwork_notification_data", json.toString())
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val pending = PendingIntent.getActivity(this, (data["order_id"] ?: data["repair_id"] ?: System.currentTimeMillis()).toString().hashCode(), openIntent, pendingFlags)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
        } else {
            android.app.Notification.Builder(this).setPriority(android.app.Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(android.app.Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify((data["order_id"] ?: data["repair_id"] ?: System.currentTimeMillis()).toString().hashCode(), notification)
    }

    private fun readNotificationIntent(source: Intent?): Map<String, Any>? {
        val raw = source?.getStringExtra("pcwork_notification_data") ?: return null
        return try {
            val json = JSONObject(raw)
            val result = mutableMapOf<String, Any>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.opt(key)
                if (value != null && value != JSONObject.NULL) result[key] = value.toString()
            }
            result
        } catch (_: Exception) { null }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val data = readNotificationIntent(intent) ?: return
        val channel = notificationMethodChannel
        if (channel != null) channel.invokeMethod("onNotificationTapped", data)
        else pendingNotificationData = data
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

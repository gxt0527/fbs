package com.example.fbs

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.example.fbs.service.BackScreenController
import com.example.fbs.service.FBSForegroundService
import com.example.fbs.service.FBSNotificationListenerService
import com.example.fbs.service.PermissionHelper

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.example.fbs/native"
    private val EVENT_CHANNEL = "com.example.fbs/notification_events"

    private lateinit var backScreenController: BackScreenController
    private var eventChannel: EventChannel? = null
    private var flutterMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backScreenController = BackScreenController(this)
        backScreenController.initialize()

        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)

        flutterMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    result.success(isNotificationListenerEnabled())
                }
                "openNotificationListenerSettings" -> {
                    PermissionHelper.openNotificationListenerSettings(this)
                    result.success(true)
                }
                "startForegroundService" -> {
                    FBSForegroundService.startService(this)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    FBSForegroundService.stopService(this)
                    result.success(true)
                }
                "rebindNotificationListener" -> {
                    FBSNotificationListenerService.requestRebind(this)
                    result.success(true)
                }
                "isShizukuRunning" -> {
                    result.success(backScreenController.isShizukuRunning())
                }
                "hasShizukuPermission" -> {
                    result.success(backScreenController.hasPermission())
                }
                "requestShizukuPermission" -> {
                    backScreenController.requestPermission { granted ->
                        runOnUiThread {
                            flutterMethodChannel?.invokeMethod(
                                "onShizukuPermissionResult",
                                mapOf("granted" to granted)
                            )
                        }
                    }
                    result.success(true)
                }
                "getInstalledApps" -> {
                    val useShizuku = call.argument<Boolean>("useShizuku") ?: false
                    if (useShizuku && backScreenController.isShizukuRunning() && backScreenController.hasPermission()) {
                        backScreenController.getInstalledAppsViaShizuku { apps ->
                            runOnUiThread { result.success(apps) }
                        }
                    } else {
                        result.success(getInstalledApps())
                    }
                }
                "requestAppListPermission" -> {
                    PermissionHelper.openAppDetailsSettings(this)
                    result.success(true)
                }
                "displayOnBackScreen" -> {
                    val title = call.argument<String>("title") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    backScreenController.displayOnBackScreen(title, content)
                    result.success(true)
                }
                "removePinByNotificationId" -> {
                    val id = call.argument<Int>("notificationId") ?: 0
                    backScreenController.removePinByNotificationId(id)
                    result.success(true)
                }
                "clearAllPins" -> {
                    backScreenController.clearAllPinsAndBackToIdle()
                    result.success(true)
                }
                "wakeUpScreen" -> {
                    backScreenController.wakeUpScreen()
                    result.success(true)
                }
                "setScreenTimeout" -> {
                    val millis = call.argument<Int>("millis") ?: 90000
                    backScreenController.setScreenTimeout(millis)
                    result.success(true)
                }
                "setBackScreenBrightness" -> {
                    val brightness = call.argument<Int>("brightness") ?: 128
                    backScreenController.setBackScreenBrightness(brightness)
                    result.success(true)
                }
                "sleepBackScreen" -> {
                    backScreenController.sleepBackScreen()
                    result.success(true)
                }
                // === 澎湃OS 权限引导相关方法 ===
                "isInstalledAppsPermissionSupported" -> {
                    result.success(PermissionHelper.isInstalledAppsPermissionSupported(this))
                }
                "isInstalledAppsPermissionGranted" -> {
                    result.success(PermissionHelper.isInstalledAppsPermissionGranted(this))
                }
                "requestInstalledAppsPermission" -> {
                    PermissionHelper.requestInstalledAppsPermission(this)
                    result.success(true)
                }
                "isPostNotificationsGranted" -> {
                    result.success(PermissionHelper.isPostNotificationsGranted(this))
                }
                "requestPostNotifications" -> {
                    PermissionHelper.requestPostNotifications(this)
                    result.success(true)
                }
                "openAutoStartSettings" -> {
                    val ok = PermissionHelper.openAutoStartSettings(this)
                    result.success(ok)
                }
                "openBatteryOptimizationSettings" -> {
                    PermissionHelper.openBatteryOptimizationSettings(this)
                    result.success(true)
                }
                "openBackgroundPopSettings" -> {
                    PermissionHelper.openBackgroundPopSettings(this)
                    result.success(true)
                }
                "openOverlaySettings" -> {
                    PermissionHelper.openOverlaySettings(this)
                    result.success(true)
                }
                "openAppDetailsSettings" -> {
                    PermissionHelper.openAppDetailsSettings(this)
                    result.success(true)
                }
                "isMiuiOrHyperOS" -> {
                    result.success(PermissionHelper.isMiuiOrHyperOS())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Event channel for notification events to Flutter
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                FBSNotificationListenerService.setEventSink(events)
                Log.d("MainActivity", "EventChannel onListen")
            }

            override fun onCancel(arguments: Any?) {
                FBSNotificationListenerService.setEventSink(null)
                Log.d("MainActivity", "EventChannel onCancel")
            }
        })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = PermissionHelper.onRequestPermissionsResult(
            requestCode, permissions, grantResults
        )
        if (granted != null) {
            flutterMethodChannel?.invokeMethod(
                "onInstalledAppsPermissionResult",
                mapOf("granted" to granted)
            )
        }
        if (requestCode == PermissionHelper.REQUEST_CODE_POST_NOTIFICATIONS) {
            val g = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            flutterMethodChannel?.invokeMethod(
                "onPostNotificationsPermissionResult",
                mapOf("granted" to g)
            )
        }
    }

    override fun onResume() {
        super.onResume()
        flutterMethodChannel?.invokeMethod("onPermissionScreenResumed", null)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat?.contains(packageName) == true || flat?.contains(
            ComponentName(this, FBSNotificationListenerService::class.java).flattenToString()
        ) == true
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val apps = mutableListOf<Map<String, String>>()
        try {
            val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getInstalledApplications(
                    PackageManager.ApplicationInfoFlags.of(PackageManager.MATCH_ALL.toLong()))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledApplications(PackageManager.GET_ACTIVITIES or PackageManager.MATCH_ALL)
            }

            for (ai in installedApps) {
                if (ai.packageName == packageName) continue
                val isSystem = try {
                    (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                } catch (e: Exception) { false }
                if (isSystem) continue
                try {
                    val name = packageManager.getApplicationLabel(ai).toString()
                    apps.add(mapOf("package" to ai.packageName, "name" to name))
                } catch (_: Exception) { }
            }
            apps.sortBy { it["name"] }
            Log.d("MainActivity", "getInstalledApps: ${apps.size} apps")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting installed apps", e)
        }
        return apps
    }

    override fun onDestroy() {
        super.onDestroy()
        backScreenController.destroy()
    }
}

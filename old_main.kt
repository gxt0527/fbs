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
        BackScreenController.instance = backScreenController
        FBSNotificationListenerService.backScreenController = backScreenController

        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)

        flutterMethodChannel?.setMethodCallHandler { call, result ->
            Log.d("MainActivity", ">>> methodCallHandler: ${call.method}")
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
                    // API 34+ requestRebind is deprecated; toggle the component
                    val cn = ComponentName(this, FBSNotificationListenerService::class.java)
                    packageManager.setComponentEnabledSetting(cn,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP)
                    packageManager.setComponentEnabledSetting(cn,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP)
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
                    // Shizuku 浠呯敤浜庤儗灞忔搷浣滐紝搴旂敤鍒楄〃璧板畼鏂?GET_INSTALLED_APPS 閫氶亾
                    result.success(getInstalledApps())
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
                // V2: MRSS 椋庢牸 鈥?鑷畾涔夋覆鏌?Activity 鎶曞睆鍒?display 1
                "displayOnBackScreenV2" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val packageName = call.argument<String>("packageName") ?: ""
                    @Suppress("UNCHECKED_CAST")
                    val styleExtras = (call.argument<Map<String, Any>>("styleExtras")
                        ?: emptyMap<String, Any>())
                        .mapValues { it.value.toString() }
                    backScreenController.displayNotificationOnBackScreenV2(
                        title = title,
                        subtitle = subtitle,
                        content = content,
                        appName = appName,
                        packageName = packageName,
                        styleExtras = styleExtras,
                    )
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
                // === 婢庢箖OS 鏉冮檺寮曞鐩稿叧鏂规硶 ===
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
                "sendIslandTestNotification" -> {
                    sendIslandTestNotification()
                    result.success(true)
                }
                "getIslandDiagnostics" -> {
                    val diag = com.example.fbs.service.SuperIslandHelper.getDiagnostics(this)
                    result.success(diag)
                }
                "openFocusNotificationSettings" -> {
                    com.example.fbs.service.SuperIslandHelper.openFocusNotificationSettings(this)
                    result.success(true)
                }
                "openAppDetailsSettings" -> {
                    PermissionHelper.openAppDetailsSettings(this)
                    result.success(true)
                }
                "updateMonitorSettings" -> {
                    val monitorAll = call.argument<Boolean>("monitorAll") ?: true
                    @Suppress("UNCHECKED_CAST")
                    val enabledApps = call.argument<List<String>>("enabledApps") ?: emptyList()
                    FBSNotificationListenerService.updateMonitorSettings(monitorAll, enabledApps)
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

        // 棣栨鍚姩鏃跺彂閫佽秴绾у矝娴嬭瘯閫氱煡
        val prefs = getSharedPreferences("fbs_island_test", MODE_PRIVATE)
        if (!prefs.getBoolean("launched", false)) {
            prefs.edit().putBoolean("launched", true).apply()
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                sendIslandTestNotification()
            }, 2000)
        }
    }

    /**
     * 鍙戦€佽秴绾у矝娴嬭瘯閫氱煡锛屼緵 Flutter 璋冪敤鍜岃嚜鍔ㄨЕ鍙戜娇鐢ㄣ€?     */
    private fun sendIslandTestNotification() {
        try {
            val supported = com.example.fbs.service.SuperIslandHelper.isIslandSupported(this)
            Log.d("MainActivity", "islandSupported=$supported")
            if (supported) {
                com.example.fbs.service.SuperIslandHelper.sendTestIslandNotification(this)
                Log.d("MainActivity", "Super Island test notification sent")
            } else {
                // 鍗充娇涓嶆敮鎸佸矝锛屼篃鍙戞櫘閫氶€氱煡娴嬭瘯鏉冮檺鏄惁姝ｅ父
                com.example.fbs.service.SuperIslandHelper.sendTestIslandNotification(this)
                Log.d("MainActivity", "Island not supported, sent as鏅€氶€氱煡")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "Failed to send island test notification", e)
        }
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
                    PackageManager.ApplicationInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledApplications(0)
            }

            Log.d("MainActivity", "getInstalledApps: raw count = ${installedApps.size}")

            var skippedSelf = 0
            for (ai in installedApps) {
                if (ai.packageName == packageName) {
                    skippedSelf++
                    continue
                }
                try {
                    val name = packageManager.getApplicationLabel(ai).toString()
                    val isSystem = try {
                        (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    } catch (_: Exception) { false }
                    val entry = mapOf(
                        "package" to ai.packageName,
                        "name" to name,
                        "isSystem" to isSystem.toString(),
                    )
                    apps.add(entry)
                } catch (_: Exception) {}
            }
            // 绯荤粺搴旂敤鎺掑悗闈紝鐢ㄦ埛搴旂敤鎺掑墠闈?            apps.sortWith(compareBy<Map<String, String>> { it["isSystem"] == "true" }.thenBy { it["name"] })
            Log.d("MainActivity",
                "getInstalledApps: total=${installedApps.size} self=$skippedSelf user=${apps.size}")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting installed apps", e)
            tryFallbackInstalledPackages(apps)
        }
        return apps
    }

    @Suppress("DEPRECATION")
    private fun tryFallbackInstalledPackages(apps: MutableList<Map<String, String>>) {
        try {
            val pkgs = packageManager.getInstalledPackages(0)
            Log.d("MainActivity", "fallback getInstalledPackages: ${pkgs.size} pkgs")
            for (pi in pkgs) {
                if (pi.packageName == packageName) continue
                val ai = pi.applicationInfo ?: continue
                try {
                    val name = ai.loadLabel(packageManager).toString()
                    val isSystem = try {
                        (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    } catch (_: Exception) { false }
                    apps.add(mapOf(
                        "package" to pi.packageName,
                        "name" to name,
                        "isSystem" to isSystem.toString(),
                    ))
                } catch (_: Exception) {}
            }
            apps.sortWith(compareBy<Map<String, String>> { it["isSystem"] == "true" }.thenBy { it["name"] })
            Log.d("MainActivity", "fallback getInstalledPackages: ${apps.size} apps")
        } catch (e: Exception) {
            Log.e("MainActivity", "fallback also failed", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        backScreenController.destroy()
        if (BackScreenController.instance === backScreenController) {
            BackScreenController.instance = null
        }
    }
}

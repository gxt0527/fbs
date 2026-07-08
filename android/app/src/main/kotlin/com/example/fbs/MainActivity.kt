package com.example.fbs

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.fbs.service.BackScreenController
import com.example.fbs.service.PermissionHelper

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.example.fbs/native"

    private lateinit var backScreenController: BackScreenController
    private var flutterMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backScreenController = BackScreenController(this)
        backScreenController.initialize()
        BackScreenController.instance = backScreenController

        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)

        flutterMethodChannel?.setMethodCallHandler { call, result ->
            Log.d("MainActivity", ">>> methodCallHandler: ${call.method}")
            when (call.method) {
                // Shizuku
                "isShizukuRunning" -> { result.success(backScreenController.isShizukuRunning()) }
                "hasShizukuPermission" -> { result.success(backScreenController.hasPermission()) }
                "requestShizukuPermission" -> {
                    backScreenController.requestPermission { granted ->
                        runOnUiThread {
                            flutterMethodChannel?.invokeMethod("onShizukuPermissionResult", mapOf("granted" to granted))
                        }
                    }
                    result.success(true)
                }

                // 背屏转发
                "displayOnBackScreenV2" -> {
                    backScreenController.displayOnBackScreenV2(
                        title = call.argument<String>("title") ?: "",
                        subtitle = call.argument<String>("subtitle") ?: "",
                        content = call.argument<String>("content") ?: "",
                        appName = call.argument<String>("appName") ?: "",
                    )
                    result.success(true)
                }
                "dismissBackScreen" -> {
                    backScreenController.dismissBackScreen()
                    result.success(true)
                }

                // 超级岛
                "sendSuperIslandNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    com.example.fbs.service.SuperIslandHelper.sendNotification(this, title, content)
                    result.success(true)
                }
                "cancelSuperIslandNotification" -> {
                    com.example.fbs.service.SuperIslandHelper.cancelNotification(this)
                    result.success(true)
                }
                "hasPromotedNotificationPermission" -> {
                    result.success(com.example.fbs.service.SuperIslandHelper.hasPromotedPermission(this))
                }
                "requestPromotedNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        requestPermissions(arrayOf("android.permission.POST_PROMOTED_NOTIFICATIONS"), 2001)
                    }
                    result.success(true)
                }
                "openFocusNotificationSettings" -> {
                    com.example.fbs.service.SuperIslandHelper.openFocusNotificationSettings(this)
                    result.success(true)
                }

                // 应用列表
                "getInstalledApps" -> {
                    result.success(getInstalledApps())
                }

                // 权限
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
                    result.success(PermissionHelper.openAutoStartSettings(this))
                }
                "openBatteryOptimizationSettings" -> {
                    PermissionHelper.openBatteryOptimizationSettings(this)
                    result.success(true)
                }
                "openAppDetailsSettings" -> {
                    PermissionHelper.openAppDetailsSettings(this)
                    result.success(true)
                }
                "isMiuiOrHyperOS" -> { result.success(PermissionHelper.isMiuiOrHyperOS()) }

                else -> { result.notImplemented() }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        flutterMethodChannel?.invokeMethod("onResumed", null)
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val apps = mutableListOf<Map<String, String>>()
        try {
            val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledApplications(0)
            }
            for (ai in installedApps) {
                if (ai.packageName == packageName) continue
                try {
                    val name = packageManager.getApplicationLabel(ai).toString()
                    val isSystem = (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    apps.add(mapOf("package" to ai.packageName, "name" to name, "isSystem" to isSystem.toString()))
                } catch (_: Exception) {}
            }
            apps.sortWith(compareBy<Map<String, String>> { it["isSystem"] == "true" }.thenBy { it["name"] })
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting installed apps", e)
        }
        return apps
    }

    override fun onDestroy() {
        super.onDestroy()
        backScreenController.destroy()
        if (BackScreenController.instance === backScreenController) {
            BackScreenController.instance = null
        }
    }
}

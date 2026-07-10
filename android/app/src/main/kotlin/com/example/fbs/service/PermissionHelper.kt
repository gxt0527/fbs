package com.example.fbs.service

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

object PermissionHelper {

    private const val TAG = "PermissionHelper"
    const val REQUEST_CODE_INSTALLED_APPS = 9001
    const val REQUEST_CODE_POST_NOTIFICATIONS = 9002

    // 提供方仅 MIUI 13+ / 澎湃OS 存在
    private const val INSTALLED_APPS_PROVIDER = "com.lbe.security.miui"

    // ===================================================================
    //  应用列表权限（澎湃OS "获取应用列表"运行时权限）
    // ===================================================================

    /**
     * 是否支持动态申请"获取应用列表"权限
     * 仅 MIUI 13+ / 澎湃OS 支持
     * 按官方文档：通过 getPermissionInfo 检查该权限是否由 com.lbe.security.miui 提供
     * https://dev.mi.com/xiaomihyperos/documentation/detail?pId=1619
     */
    fun isInstalledAppsPermissionSupported(context: Context): Boolean {
        return try {
            val pi = context.packageManager.getPermissionInfo(
                "com.android.permission.GET_INSTALLED_APPS", 0
            )
            val supported = pi.packageName == INSTALLED_APPS_PROVIDER
            Log.d(TAG, "isInstalledAppsPermissionSupported: $supported " +
                    "(permissionInfo.packageName=${pi.packageName}, expected=$INSTALLED_APPS_PROVIDER)")
            supported
        } catch (e: PackageManager.NameNotFoundException) {
            Log.d(TAG, "isInstalledAppsPermissionSupported: false (permission not found)")
            false
        }
    }

    /**
     * "获取应用列表"权限是否已授予
     * 权限名: com.android.permission.GET_INSTALLED_APPS
     */
    fun isInstalledAppsPermissionGranted(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            "com.android.permission.GET_INSTALLED_APPS"
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * 请求"获取应用列表"运行时权限
     */
    fun requestInstalledAppsPermission(activity: Activity) {
        if (!isInstalledAppsPermissionSupported(activity)) {
            Log.d(TAG, "Installed apps permission not supported, fallback to app details")
            openAppDetailsSettings(activity)
            return
        }
        try {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf("com.android.permission.GET_INSTALLED_APPS"),
                REQUEST_CODE_INSTALLED_APPS
            )
        } catch (e: Exception) {
            Log.e(TAG, "requestInstalledAppsPermission failed", e)
            openAppDetailsSettings(activity)
        }
    }

    // ===================================================================
    //  POST_NOTIFICATIONS 权限（Android 13+）
    // ===================================================================

    fun isPostNotificationsGranted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun requestPostNotifications(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_CODE_POST_NOTIFICATIONS
            )
        }
    }

    // ===================================================================
    //  onRequestPermissionsResult 分发
    // ===================================================================

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean? {
        if (requestCode == REQUEST_CODE_INSTALLED_APPS) {
            return grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
        }
        return null
    }

    // ===================================================================
    //  通知监听权限
    // ===================================================================

    fun openNotificationListenerSettings(context: Context) {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openNotificationListenerSettings failed", e)
        }
    }

    // ===================================================================
    //  自启动 / 后台 / 电池 / 悬浮窗 / 应用详情
    // ===================================================================

    fun openAppNotificationSettings(context: Context) {
        try {
            val intent = android.content.Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            intent.putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openAppNotificationSettings failed", e)
            // fallback: 打开应用详情
            openAppDetailsSettings(context)
        }
    }

    fun isMiuiOrHyperOS(): Boolean {
        return try {
            val prop = Class.forName("android.os.SystemProperties")
                .getMethod("get", String::class.java)
                .invoke(null, "ro.miui.ui.version.name") as? String
            prop != null && prop.isNotEmpty()
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 跳转自启动设置
     * 澎湃OS: miui.intent.action.OP_AUTO_START
     * 兜底: 应用详情页
     */
    fun openAutoStartSettings(context: Context): Boolean {
        try {
            val intent = Intent("miui.intent.action.OP_AUTO_START").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                `package` = "com.miui.securitycenter"
                putExtra("package_name", context.packageName)
                putExtra("uid", context.applicationInfo.uid)
            }
            context.startActivity(intent)
            return true
        } catch (_: Exception) {}

        try {
            val intent = Intent("miui.intent.action.OP_AUTO_START").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                `package` = "com.miui.安全管理" // 部分MIUI版本包名不同
                putExtra("package_name", context.packageName)
            }
            context.startActivity(intent)
            return true
        } catch (_: Exception) {}

        return openAppDetailsSettings(context)
    }

    fun openBackgroundPopSettings(context: Context) {
        try {
            val intent = Intent("miui.intent.action.POWER_HIDE_MODE_APP").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("package_name", context.packageName)
            }
            context.startActivity(intent)
            return
        } catch (_: Exception) {}
        openAppDetailsSettings(context)
    }

    fun openBatteryOptimizationSettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openBatteryOptimizationSettings failed", e)
        }
    }

    fun openOverlaySettings(context: Context) {
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "openOverlaySettings failed", e)
        }
    }

    /**
     * 打开应用详情页（兜底方案）
     */
    fun openAppDetailsSettings(context: Context): Boolean {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                data = Uri.parse("package:${context.packageName}")
            }
            context.startActivity(intent)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "openAppDetailsSettings failed", e)
            return false
        }
    }
}

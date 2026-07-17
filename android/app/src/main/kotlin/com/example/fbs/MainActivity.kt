package com.example.fbs

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.example.fbs.service.BackScreenController
import com.example.fbs.service.FBSForegroundService
import com.example.fbs.service.FBSNotificationListenerService
import com.example.fbs.service.NativeOcrService
import com.example.fbs.service.PermissionHelper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.example.fbs/native"
    private val EVENT_CHANNEL = "com.example.fbs/notification_events"

    private lateinit var backScreenController: BackScreenController
    private lateinit var ocrService: NativeOcrService
    private var eventChannel: EventChannel? = null
    private var flutterMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        backScreenController = BackScreenController(this)
        backScreenController.initialize()
        // 通知监听服务可以通过静态引用直接访问 Controller
        com.example.fbs.service.FBSNotificationListenerService.backScreenController = backScreenController
        // 确保监听组件已启用（用户自行在系统设置打开通知使用权后自动启用）
        try {
            val cn = android.content.ComponentName(this, com.example.fbs.service.FBSNotificationListenerService::class.java)
            if (packageManager.getComponentEnabledSetting(cn) == android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                packageManager.setComponentEnabledSetting(cn,
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP)
            }
        } catch (_: Exception) {}

        // 初始化OCR服务（单例）
        ocrService = NativeOcrService.getInstance()
        lifecycleScope.launch {
            ocrService.init(this@MainActivity)
        }

        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)

        // 注册 ShareReceiverActivity 回调 — 当透明 Activity 收到分享时直接通知 Flutter
        ShareReceiverActivity.onSharedContent = { type, text, imageUri ->
            runOnUiThread {
                flutterMethodChannel?.invokeMethod("onSharedContent", mapOf(
                    "type" to type,
                    "text" to text,
                    "imageUri" to imageUri,
                ))
            }
        }

        // 处理冷启动时 Intent 携带的分享数据
        handleShareIntent(intent)

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
                    // 优先用 Shizuku（绕过 HyperOS 对 app setComponentEnabledSetting 的限制）
                    backScreenController.enableNotificationListener()
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
                    // Shizuku 仅用于背屏操作，应用列表走官方 GET_INSTALLED_APPS 通道
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
                // V2: MRSS 风格 — 自定义渲染 Activity 投屏到 display 1
                "displayOnBackScreenV2" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val appName = call.argument<String>("appName") ?: ""
                    val packageName = call.argument<String>("packageName") ?: ""
                    val category = call.argument<String>("category") ?: "general"
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
                        category = category,
                    )
                    result.success(true)
                }
                "dismissBackScreen" -> {
                    backScreenController.dismissBackScreen()
                    result.success(true)
                }
                "sendImagePin" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val r = backScreenController.renderAndPinImage(title, subtitle, content)
                    result.success(r)
                }
                "forwardSharedImage" -> {
                    val imageUri = call.argument<String>("imageUri") ?: ""
                    val r = backScreenController.forwardSharedImage(imageUri)
                    result.success(r)
                }
                // 新增：OCR识别图片文字
                "recognizeImageText" -> {
                    val imageUri = call.argument<String>("imageUri") ?: ""
                    if (imageUri.isEmpty()) {
                        result.error("INVALID_URI", "图片URI不能为空", null)
                        return@setMethodCallHandler
                    }
                    
                    // 后台线程执行，不阻塞UI
                    lifecycleScope.launch {
                        val ocrResult = ocrService.recognizeText(this@MainActivity, imageUri)
                        withContext(Dispatchers.Main) {
                            result.success(mapOf(
                                "success" to ocrResult.success,
                                "text" to ocrResult.text,
                                "lineCount" to ocrResult.lineCount,
                                "detectionTimeMs" to ocrResult.detectionTimeMs,
                                "recognitionTimeMs" to ocrResult.recognitionTimeMs,
                                "totalTimeMs" to ocrResult.totalTimeMs,
                                "errorMessage" to ocrResult.errorMessage,
                            ))
                        }
                    }
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
                "setSubDisplayBrightness" -> {
                    val brightness = call.argument<Int>("brightness") ?: 46
                    backScreenController.setSubDisplayBrightness(brightness)
                    result.success(true)
                }
                "sleepBackScreen" -> {
                    backScreenController.sleepBackScreen()
                    result.success(true)
                }
                // 超级岛 (HyperIsland-ToolKit)
                "sendSuperIslandNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val iconName = call.argument<String>("iconName") ?: "general"

                    com.example.fbs.service.SuperIslandHelper.sendNotification(
                        this, title, content, iconName
                    )
                    result.success(true)
                }
                "cancelSuperIslandNotification" -> {
                    com.example.fbs.service.SuperIslandHelper.cancelNotification(this)
                    result.success(true)
                }
                // 网络阻断转发（已验证稳定的方案）
                "sendFocusWithNetworkBypass" -> {
                    val title = call.argument<String>("title") ?: ""
                    val content = call.argument<String>("content") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val codeValue = call.argument<String>("codeValue") ?: ""
                    val category = call.argument<String>("category") ?: "general"
                    com.example.fbs.hyperisland.FocusForwarder.send(
                        this, title, content, subtitle, codeValue, category
                    )
                    result.success(true)
                }
                // 网络阻断转发 #9（模板9 — 文本组件2 + 识别图形组件1 + 按钮组件2）
                "sendFocusWithNetworkBypassTemplate9" -> {
                    val label = call.argument<String>("label") ?: ""
                    val codeValue = call.argument<String>("codeValue") ?: ""
                    val storeName = call.argument<String>("storeName") ?: ""
                    val items = call.argument<String>("items") ?: ""
                    val amount = call.argument<String>("amount") ?: ""
                    val category = call.argument<String>("category") ?: "foodDelivery"
                    com.example.fbs.hyperisland.FocusForwarder.sendTemplate9(
                        this, label, codeValue, storeName, items, amount, category
                    )
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
                "openAppNotificationSettings" -> {
                    PermissionHelper.openAppNotificationSettings(this)
                    result.success(true)
                }
                "isMiuiOrHyperOS" -> {
                    result.success(PermissionHelper.isMiuiOrHyperOS())
                }
                "showToast" -> {
                    val message = call.argument<String>("message") ?: ""
                    if (message.isNotEmpty()) {
                        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show()
                    }
                    result.success(true)
                }
                "launchHyperIslandTest" -> {
                    try {
                        startActivity(Intent(this, com.example.fbs.hyperisland.HyperIslandTestActivity::class.java))
                    } catch (e: Exception) {
                        android.util.Log.e("FBS", "launchHyperIslandTest failed", e)
                    }
                    result.success(true)
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
        handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShareIntent(intent)
    }

    /**
     * 解析 Intent 中的分享数据并通知 Flutter
     */
    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return

        when (action) {
            Intent.ACTION_PROCESS_TEXT -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                if (!text.isNullOrBlank()) {
                    Log.d("MainActivity", "PROCESS_TEXT: ${text.take(100)}")
                    flutterMethodChannel?.invokeMethod("onSharedContent", mapOf(
                        "type" to "text",
                        "text" to text,
                        "imageUri" to null as String?,
                    ))
                }
            }
            Intent.ACTION_SEND -> {
                val mimeType = intent.type ?: ""
                if (mimeType.startsWith("image/")) {
                    val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    if (uri != null) {
                        Log.d("MainActivity", "SEND image: $uri")
                        flutterMethodChannel?.invokeMethod("onSharedContent", mapOf(
                            "type" to "image",
                            "text" to null as String?,
                            "imageUri" to uri.toString(),
                        ))
                    }
                } else {
                    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    if (!text.isNullOrBlank()) {
                        Log.d("MainActivity", "SEND text: ${text.take(100)}")
                        flutterMethodChannel?.invokeMethod("onSharedContent", mapOf(
                            "type" to "text",
                            "text" to text,
                            "imageUri" to null as String?,
                        ))
                    }
                }
            }
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
            // HyperOS 上 getInstalledApplications(MATCH_ALL) 可能与 GET_INSTALLED_APPS
            // 运行时权限存在兼容性问题，先用没有标志位的调用。QUERY_ALL_PACKAGES 已声明，
            // flag=0 即可返回所有已安装的非系统独占应用。
            val installedApps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getInstalledApplications(
                    PackageManager.ApplicationInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstalledApplications(0)
            }

            Log.d("MainActivity", "getInstalledApps: raw count = ${installedApps.size}")

            var skippedSelf = 0
            var skippedSystem = 0
            for (ai in installedApps) {
                if (ai.packageName == packageName) {
                    skippedSelf++
                    continue
                }
                val isSystem = try {
                    (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                } catch (e: Exception) { false }
                if (isSystem) {
                    skippedSystem++
                    Log.d("MainActivity", "getInstalledApps: skip system ${ai.packageName}")
                    continue
                }
                try {
                    val name = packageManager.getApplicationLabel(ai).toString()
                    val entry = mapOf("package" to ai.packageName, "name" to name)
                    apps.add(entry)
                    Log.d("MainActivity", "getInstalledApps: + ${ai.packageName} / $name")
                } catch (_: Exception) {
                    Log.d("MainActivity", "getInstalledApps: failed label for ${ai.packageName}")
                }
            }
            apps.sortBy { it["name"] }
            Log.d("MainActivity",
                "getInstalledApps: total=${installedApps.size} self=$skippedSelf " +
                "system=$skippedSystem user=${apps.size}")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error getting installed apps", e)
            // 兜底：尝试用 getInstalledPackages
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
                val isSystem = try {
                    (ai.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                } catch (e: Exception) { false }
                if (isSystem) continue
                try {
                    val name = ai.loadLabel(packageManager).toString()
                    apps.add(mapOf("package" to pi.packageName, "name" to name))
                } catch (_: Exception) {}
            }
            apps.sortBy { it["name"] }
            Log.d("MainActivity", "fallback getInstalledPackages: ${apps.size} user apps")
        } catch (e: Exception) {
            Log.e("MainActivity", "fallback also failed", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        backScreenController.destroy()
    }
}

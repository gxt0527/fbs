package com.example.fbs.service

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap

/**
 * 鑳屽睆鎺у埗鍣?鈥?缁熶竴绠＄悊閫氱煡鍒拌儗灞忕殑杞彂銆? *
 * 鍙敤鎺ュ彛锛堢粡娴嬭瘯锛?
 * 1. am start NotificationActivity + service call activity_task 50 鈫?鑷畾涔?UI 鍒?display 1
 * 2. PinReceiveActivity (ACTION_SEND) 鈫?鏂囨湰鎶曞睆
 * 3. input keyevent WAKEUP 鈫?鍞ら啋灞忓箷
 * 4. settings 鈫?灞忓箷瓒呮椂鎺у埗
 * 5. force-stop subscreencenter 鈫?闃叉瀹樻柟鑳屽睆鎶㈠崰
 *
 * 涓嶅彲鐢ㄦ帴鍙?
 * - SUB_SCREEN_ON/OFF 骞挎挱锛堝彈淇濇姢骞挎挱锛? * - SubScreenAppProvider锛堥渶瑕佺郴缁熸潈闄愶級
 * - statusbar.notification锛堥渶瑕?STATUS_BAR_SERVICE 鏉冮檺锛? */
class BackScreenController(private val context: Context) {

    companion object {
        private const val TAG = "BackScreenController"
        private const val SUBSCREEN_PACKAGE = "com.xiaomi.subscreencenter"
        private const val REQUEST_CODE_SHIZUKU = 1001

        private var lastForwardTime = 0L
        private val GLOBAL_COOLDOWN_MS = 800L

        // MainActivity 鍒涘缓 controller 鏃舵敞鍐岃繖涓潤鎬佸紩鐢紝
        // 璁?BackScreenNotificationActivity 涓嶄緷璧?MainActivity 瀹炰緥鍗冲彲璋冪敤 Shizuku 閲嶅惎绯荤粺鑳屽睆銆?        @Volatile
        var instance: BackScreenController? = null

        /**
         * 缂撳瓨鏈€杩戜竴娆￠€氳繃 Flutter 浼犲叆鐨勬牱寮忓弬鏁般€?         * 绯荤粺 NotificationListener 杞彂閫氱煡鏃朵笉甯?styleExtras锛?         * 鐢ㄦ缂撳瓨纭繚鎽勫儚澶撮伩璁╃瓑璁剧疆涓嶄涪澶便€?         */
        @Volatile
        var latestStyleExtras: Map<String, String> = emptyMap()
    }

    // 鈹€鈹€ 閫氱煡杩借釜 鈹€鈹€
    // 鎵€鏈夊緟鏄剧ず鐨勯€氱煡: key 鈫?NotifInfo
    private val activeNotifications = ConcurrentHashMap<String, NotifInfo>()
    // 鐒︾偣閫氱煡鐨?key 闆嗗悎锛堜笉鍙楄秴鏃堕檺鍒讹級
    private val focusNotificationKeys = mutableSetOf<String>()
    // 褰撳墠鏄剧ず鐨?notificationKey
    private var currentDisplayKey: String? = null

    data class NotifInfo(
        val key: String,
        val title: String,
        val content: String,
        val packageName: String,
        val appName: String,
        val isFocus: Boolean,
        val isOngoing: Boolean,
        val category: String,
        val subText: String,
        val bigText: String,
        val timestamp: Long,
    )

    // 鈹€鈹€ Shizuku 鈹€鈹€

    private var permissionCallback: ((Boolean) -> Unit)? = null

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        Log.d(TAG, "Shizuku binder received!")
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        Log.d(TAG, "Shizuku binder dead")
    }

    private val permissionResultListener =
        Shizuku.OnRequestPermissionResultListener { _, grantResult ->
            val granted = grantResult == PackageManager.PERMISSION_GRANTED
            permissionCallback?.invoke(granted)
            permissionCallback = null
        }

    fun initialize() {
        Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
        Shizuku.addBinderDeadListener(binderDeadListener)
        Shizuku.addRequestPermissionResultListener(permissionResultListener)
    }

    fun isShizukuRunning() = try { Shizuku.pingBinder() } catch (_: Exception) { false }
    fun hasPermission() = try {
        isShizukuRunning() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Exception) { false }

    fun requestPermission(callback: (Boolean) -> Unit) {
        permissionCallback = callback
        try {
            if (!Shizuku.pingBinder() || Shizuku.isPreV11()) { callback(false); permissionCallback = null; return }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) { callback(true); permissionCallback = null; return }
            Shizuku.requestPermission(REQUEST_CODE_SHIZUKU)
        } catch (e: Exception) { callback(false); permissionCallback = null }
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  鏍稿績: 閫氱煡鏂板 / 鏇存柊
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    /**
     * 閫氱煡鍒拌揪 鈥?璁板綍骞舵帹閫佸埌鑳屽睆
     * @param styleExtras 鑷畾涔夋牱寮忓弬鏁?(棰滆壊/瀛椾綋/澶у皬绛?
     */
    fun onNotificationAdded(
        key: String,
        title: String,
        content: String,
        packageName: String,
        appName: String,
        isFocus: Boolean,
        isOngoing: Boolean,
        category: String,
        subText: String,
        bigText: String,
        styleExtras: Map<String, String> = emptyMap(),
    ) {
        // 缂撳瓨 Flutter 浼犲叆鐨勬牱寮忥紙鍚憚鍍忓ご閬胯鍙傛暟锛夛紝
        // 绯荤粺 NotificationListener 璺緞涓嶄紶 styleExtras 鏃朵娇鐢ㄧ紦瀛樺€?        if (styleExtras.isNotEmpty()) {
            latestStyleExtras = styleExtras
        }

        val info = NotifInfo(
            key = key, title = title, content = content,
            packageName = packageName, appName = appName,
            isFocus = isFocus, isOngoing = isOngoing,
            category = category, subText = subText, bigText = bigText,
            timestamp = System.currentTimeMillis(),
        )

        val isUpdate = activeNotifications.containsKey(key)
        activeNotifications[key] = info

        if (isFocus) {
            focusNotificationKeys.add(key)
        }

        Log.d(TAG, "onNotification${if (isUpdate) "Updated" else "Added"}: key=$key focus=$isFocus count=${activeNotifications.size}")

        if (isFocus || activeNotifications.size == 1) {
            // 鐒︾偣閫氱煡: 濮嬬粓鏄剧ず鏈€鏂?            // 棣栨潯閫氱煡: 绔嬪嵆鏄剧ず
            pushToBackScreen(info, styleExtras, isUpdate)
        }
        // 澶氭潯鏅€氶€氱煡: 鍙帹鏈€鏂?+ 鎶樺彔璁℃暟锛屼笉閫愭潯鎺ㄩ€?        // pushToBackScreen 鏂规硶鍐呴儴浼氬鐞嗘姌鍙犻€昏緫
    }

    /**
     * 閫氱煡琚竻闄?鈥?鍚屾绉婚櫎鑳屽睆
     */
    fun onNotificationRemoved(key: String) {
        val wasFocus = focusNotificationKeys.remove(key)
        val info = activeNotifications.remove(key)

        Log.d(TAG, "onNotificationRemoved: key=$key wasFocus=$wasFocus remaining=${activeNotifications.size}")

        if (activeNotifications.isEmpty()) {
            // 鍏ㄩ儴娓呴櫎 鈫?鏉€鑳屽睆 Activity
            dismissBackScreen()
        } else if (wasFocus && currentDisplayKey == key) {
            // 褰撳墠鏄剧ず鐨勭劍鐐归€氱煡琚竻闄?鈫?鏄剧ず涓嬩竴鏉?            val latest = getLatestNotification()
            if (latest != null) {
                pushToBackScreen(latest, emptyMap(), false)
            }
        } else if (activeNotifications.size == 1) {
            // 鍙墿涓€鏉?鈫?鏄剧ず閭ｆ潯锛堝彲鑳芥槸鐒︾偣锛?            val last = activeNotifications.values.first()
            pushToBackScreen(last, emptyMap(), false)
        }
        // 澶氭潯鏅€氶€氱煡: 鎶樺彔璁℃暟浼氳嚜鍔ㄨ皟鏁?(notificationCount)
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  鎺ㄩ€佸埌鑳屽睆
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    private fun pushToBackScreen(
        info: NotifInfo,
        styleExtras: Map<String, String>,
        isUpdate: Boolean,
    ) {
        val now = System.currentTimeMillis()
        if (now - lastForwardTime < GLOBAL_COOLDOWN_MS) {
            Log.d(TAG, "Cooldown, delay push for ${info.key}")
            // 寤惰繜鍐嶆帹
            Thread {
                Thread.sleep(GLOBAL_COOLDOWN_MS)
                doPush(info, styleExtras, isUpdate)
            }.apply { isDaemon = true }.start()
            return
        }
        lastForwardTime = now
        doPush(info, styleExtras, isUpdate)
    }

    private fun doPush(info: NotifInfo, styleExtras: Map<String, String>, isUpdate: Boolean) {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.e(TAG, "Shizuku unavailable, skip push")
            return
        }

        currentDisplayKey = info.key

        try {
            // 1. 鍞ら啋
            execShizukuShell("input keyevent KEYCODE_WAKEUP")

            // 2. 鏋勫缓鍚姩鍛戒护锛堝厛 display 0锛屽啀 move 鍒?display 1锛?            val launchCmd = buildLaunchCommand(info, styleExtras)
            val launchResult = execShizukuShell(launchCmd)
            Log.d(TAG, "Launch: $launchResult")
            Thread.sleep(300)

            // 3. 绉诲睆 + 鏉€瀹樻柟鑳屽睆
            val taskId = getOurTaskId()
            if (taskId > 0) {
                execShizukuShell("service call activity_task 50 i32 $taskId i32 1; am force-stop $SUBSCREEN_PACKAGE")
                Log.d(TAG, "Moved task $taskId 鈫?display 1, killed subscreencenter")
            } else {
                Log.w(TAG, "No taskId found for BackScreenNotificationActivity")
            }

            // 4. 纭繚浜睆涓嶇伃
            execShizukuShell("settings put system screen_off_timeout 90000")

        } catch (e: Exception) {
            Log.e(TAG, "Push failed", e)
        }
    }

    /**
     * 鏋勫缓 am start 鍛戒护
     */
    private fun buildLaunchCommand(info: NotifInfo, styleExtras: Map<String, String>): String {
        // 鍚堝苟缂撳瓨鏍峰紡锛氱郴缁?NotificationListener 璺緞涓嶄紶 styleExtras 鏃朵娇鐢ㄧ紦瀛樺€?        val mergedExtras = if (styleExtras.isEmpty() && latestStyleExtras.isNotEmpty()) {
            Log.d(TAG, "Using cached styleExtras (cameraAvoid=${latestStyleExtras["cameraAvoidanceEnabled"]})")
            latestStyleExtras
        } else {
            styleExtras
        }

        val sb = StringBuilder("am start")
        sb.append(" -n ${context.packageName}/.service.BackScreenNotificationActivity")
        sb.append(" -f 0x10000000") // FLAG_ACTIVITY_NEW_TASK
        if (activeNotifications.containsKey(info.key)) {
            sb.append(" -f 0x20000000") // FLAG_ACTIVITY_SINGLE_TOP 鈫?瑙﹀彂 onNewIntent
        }
        sb.append(" --user 0")

        // 閫氱煡瀛楁
        appendExtra(sb, "title", info.title)
        appendExtra(sb, "subtitle", info.subText)
        appendExtra(sb, "content", info.content)
        appendExtra(sb, "appName", info.appName)
        appendExtra(sb, "packageName", info.packageName)
        appendExtra(sb, "category", info.category)
        appendExtra(sb, "notificationKey", info.key)
        appendExtra(sb, "isFocus", info.isFocus.toString())
        appendExtra(sb, "isSticky", info.isFocus.toString()) // 鐒︾偣閫氱煡 = 绮樻€?        appendExtra(sb, "notificationCount", activeNotifications.size.toString())

        // 璁℃暟澶т簬 1 鏃讹紝鍐呭灞曠ず鎶樺彔淇℃伅
        if (activeNotifications.size > 1 && !info.isFocus) {
            appendExtra(sb, "notificationCount", activeNotifications.size.toString())
        }

        // 鑷畾涔夋牱寮忥紙浣跨敤鍚堝苟鍚庣殑缂撳瓨锛?        appendExtra(sb, "titleFontSize", mergedExtras["titleFontSize"] ?: "28")
        appendExtra(sb, "subtitleFontSize", mergedExtras["subtitleFontSize"] ?: "20")
        appendExtra(sb, "contentFontSize", mergedExtras["contentFontSize"] ?: "16")
        appendExtra(sb, "titleColor", mergedExtras["titleColor"] ?: "#FFFFFF")
        appendExtra(sb, "subtitleColor", mergedExtras["subtitleColor"] ?: "#B0B0B0")
        appendExtra(sb, "contentColor", mergedExtras["contentColor"] ?: "#E0E0E0")
        appendExtra(sb, "backgroundColor", mergedExtras["backgroundColor"] ?: "#1A1A2E")
        appendExtra(sb, "padding", mergedExtras["padding"] ?: "24")
        appendExtra(sb, "spacing", mergedExtras["spacing"] ?: "12")
        appendExtra(sb, "showAppIcon", mergedExtras["showAppIcon"] ?: "true")
        appendExtra(sb, "showTimestamp", mergedExtras["showTimestamp"] ?: "true")
        appendExtra(sb, "cameraAvoidanceEnabled", mergedExtras["cameraAvoidanceEnabled"] ?: "false")
        appendExtra(sb, "horizontalOffset", mergedExtras["horizontalOffset"] ?: "0")

        // 闈炵劍鐐归€氱煡瓒呮椂
        if (!info.isFocus) {
            appendExtra(sb, "displayDurationMs", mergedExtras["displayDurationMs"] ?: "8000")
        }

        return sb.toString()
    }

    private fun appendExtra(sb: StringBuilder, key: String, value: String) {
        val escaped = value.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\$", "\\\$")
            .replace("'", "\\'")
        sb.append(" --es $key \"$escaped\"")
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  鑳屽睆绠＄悊
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    /**
     * 鎭㈠瀹樻柟鑳屽睆 (subscreencenter) 鍒?display 1銆?     *
     * 鏂规锛歛m start --display 1 鍦ㄥ皬绫宠澶囦笂浼氳绯荤粺 abort锛?show on rear display"锛夛紝
     * 鎵€浠ユ敼鐢ㄥ凡楠岃瘉鍙敤鐨勭粍鍚堬細
     *   1. am start -n <component>  鈫?鍚姩鍒?display 0
     *   2. service call activity_task 50 i32 <taskId> i32 1  鈫?绉诲埌 display 1
     *
     * Shizuku 涓嶅彲鐢ㄦ椂閫€鍖栦负鏅€?startActivity锛堣嚦灏戣兘鎷夎捣鍖咃級銆?     */
    fun restoreSystemBackScreenOnSubscreen() {
        if (!isShizukuRunning() || !hasPermission()) {
            Log.w(TAG, "Shizuku unavailable, restore via startActivity fallback")
            try {
                val intent = context.packageManager.getLaunchIntentForPackage(SUBSCREEN_PACKAGE)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Restore subscreen fallback failed", e)
            }
            return
        }
        try {
            // Step 1: force-stop 娓呴櫎鏃у疄渚?            execShizukuShell("am force-stop $SUBSCREEN_PACKAGE")
            Thread.sleep(200)

            // Step 2: 鍚姩 subscreencenter锛堜細鍦?display 0 鍑虹幇锛?            val launchIntent = context.packageManager.getLaunchIntentForPackage(SUBSCREEN_PACKAGE)
            if (launchIntent == null) {
                Log.w(TAG, "Cannot find subscreen launch intent")
                return
            }
            val componentName = launchIntent.component
            if (componentName != null) {
                execShizukuShell(
                    "am start --user 0 -n ${componentName.flattenToShortString()}"
                )
            } else {
                execShizukuShell(
                    "monkey -p $SUBSCREEN_PACKAGE -c android.intent.category.LAUNCHER 1"
                )
            }
            Log.d(TAG, "Started subscreencenter on display 0")

            // Step 3: 绛夊緟鍚姩瀹屾垚鍚庯紝鎵惧埌鍏?taskId 骞剁Щ鍒?display 1
            Thread.sleep(500)
            val taskId = findTaskIdForPackage(SUBSCREEN_PACKAGE)
            if (taskId > 0) {
                execShizukuShell(
                    "service call activity_task 50 i32 $taskId i32 1"
                )
                Log.d(TAG, "Moved subscreen task $taskId 鈫?display 1")
            } else {
                Log.w(TAG, "Cannot find subscreencenter task to move")
            }
        } catch (e: Exception) {
            Log.e(TAG, "restoreSystemBackScreenOnSubscreen failed", e)
        }
    }

    /** 鍦?am stack list 杈撳嚭閲屾煡鎵剧粰 packageName 鐨?task id */
    private fun findTaskIdForPackage(pkg: String): Int {
        return try {
            val result = execShizukuShell("am stack list")
            for (line in result.lines()) {
                if (line.contains(pkg) && line.contains("taskId=")) {
                    return Regex("taskId=(\\d+)")
                        .find(line)?.groupValues?.get(1)?.toIntOrNull() ?: continue
                }
            }
            -1
        } catch (_: Exception) { -1 }
    }

    fun dismissBackScreen() {
        currentDisplayKey = null
        try {
            Log.d(TAG, "Dismissing back screen")

            // 鏂规1: 閫氳繃 Shizuku am start 鍙戦€?dismiss Intent锛圫INGLE_TOP 鈫?onNewIntent 鈫?finish锛?            if (isShizukuRunning() && hasPermission()) {
                val dismissCmd = BackScreenNotificationActivity.buildDismissIntent(context)
                execShizukuShell(dismissCmd)
                Log.d(TAG, "Back screen dismissed via Shizuku")
                return
            }

            // 鏂规2: Shizuku 涓嶅彲鐢紝鐩存帴 startActivity 鍙戦€?dismiss Intent
            Log.w(TAG, "Shizuku unavailable, fallback to startActivity dismiss")
            val intent = Intent(context, BackScreenNotificationActivity::class.java)
            intent.putExtra("dismiss", "true")
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            context.startActivity(intent)
            Log.d(TAG, "Back screen dismissed via startActivity")
        } catch (e: Exception) {
            Log.e(TAG, "Dismiss failed", e)
        }
    }

    /**
     * 鑾峰彇鏈€鏂伴€氱煡锛堜紭鍏堢劍鐐归€氱煡锛?     */
    private fun getLatestNotification(): NotifInfo? {
        if (activeNotifications.isEmpty()) return null
        // 浼樺厛鐒︾偣
        val focus = activeNotifications.values.firstOrNull { it.key in focusNotificationKeys }
        if (focus != null) return focus
        // 鏈€鏂版櫘閫氶€氱煡
        return activeNotifications.values.maxByOrNull { it.timestamp }
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  鍏煎鏃ф帴鍙?    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    fun displayOnBackScreen(title: String, content: String) {
        onNotificationAdded(
            key = "manual_${System.currentTimeMillis()}",
            title = title, content = content,
            packageName = context.packageName, appName = "FBS",
            isFocus = false, isOngoing = false,
            category = "", subText = "", bigText = "",
        )
    }

    fun displayNotificationOnBackScreenV2(
        title: String, subtitle: String, content: String,
        appName: String, packageName: String,
        styleExtras: Map<String, String>,
    ) {
        onNotificationAdded(
            key = "v2_${System.currentTimeMillis()}",
            title = title, content = content,
            packageName = packageName, appName = appName,
            isFocus = true, isOngoing = false,
            category = "", subText = subtitle, bigText = "",
            styleExtras = styleExtras,
        )
    }

    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?    //  杈呭姪鏂规硶
    // 鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺?
    private fun getOurTaskId(): Int {
        try {
            val result = execShizukuShell("am stack list")
            var latestId = -1
            for (line in result.lines()) {
                if (line.contains("BackScreenNotificationActivity") && line.contains("taskId=")) {
                    val id = Regex("taskId=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: continue
                    if (id > latestId) latestId = id
                }
            }
            return latestId
        } catch (e: Exception) {
            Log.e(TAG, "getTaskId error", e)
        }
        return -1
    }

    fun wakeUpScreen() {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("input keyevent KEYCODE_WAKEUP; dumpsys deviceidle disable")
    }

    fun setScreenTimeout(millis: Int = 90000) {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("settings put system screen_off_timeout $millis")
    }

    fun setBackScreenBrightness(brightness: Int = 128) {
        if (!isShizukuRunning() || !hasPermission()) return
        execShizukuShell("settings put system screen_brightness $brightness")
    }

    private fun execShizukuShell(command: String): String {
        return try {
            val execMethod = Shizuku::class.java.getDeclaredMethod(
                "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
            )
            execMethod.isAccessible = true
            val process = execMethod.invoke(null,
                arrayOf("sh", "-c", command), null, null
            ) as Process

            val output = StringBuilder()
            BufferedReader(InputStreamReader(process.inputStream)).use { r ->
                r.lineSequence().forEach { output.appendLine(it) }
            }
            BufferedReader(InputStreamReader(process.errorStream)).use { r ->
                r.lineSequence().forEach { output.appendLine("[e] $it") }
            }
            process.waitFor()
            val result = output.toString().trim()
            if (result.length > 200) Log.d(TAG, "Shell: ${result.take(200)}...")
            else Log.d(TAG, "Shell: $result")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Shell failed: $command 鈥?${e.message}")
            "ERROR: ${e.message}"
        }
    }

    fun getInstalledAppsViaShizuku(callback: (List<Map<String, String>>) -> Unit) {
        Thread {
            try {
                val newProcess = Shizuku::class.java.getDeclaredMethod(
                    "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java
                )
                newProcess.isAccessible = true
                val process = newProcess.invoke(null,
                    arrayOf("sh", "-c", "pm list packages --user 0"), null, null
                ) as Process
                val packages = mutableListOf<String>()
                BufferedReader(InputStreamReader(process.inputStream)).use { r ->
                    r.lineSequence().filter { it.startsWith("package:") }
                        .forEach { packages.add(it.removePrefix("package:").trim()) }
                }
                process.waitFor()
                var failed = 0
                val apps = packages.mapNotNull { pkg ->
                    try {
                        val ai = context.packageManager.getApplicationInfo(pkg, 0)
                        val name = context.packageManager.getApplicationLabel(ai).toString()
                        mapOf("package" to pkg, "name" to name)
                    } catch (_: Exception) { failed++; null }
                }.sortedBy { it["name"] }
                callback(apps)
            } catch (e: Exception) {
                Log.e(TAG, "getInstalledApps failed", e)
                callback(emptyList())
            }
        }.apply { isDaemon = true }.start()
    }

    fun destroy() {
        Shizuku.removeBinderReceivedListener(binderReceivedListener)
        Shizuku.removeBinderDeadListener(binderDeadListener)
        Shizuku.removeRequestPermissionResultListener(permissionResultListener)
    }
}

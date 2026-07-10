import re

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update companion + variables
old1 = '''    companion object {
        private const val TAG = "BackScreenNotif"
        private const val AOD_TRANSITION_DELAY_MS = 5000L
    }

    private var renderView: NotificationRenderView? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var isInAodMode = false
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var displayDurationMs = 10000L
    private val aodTransitionRunnable = Runnable { enterAodMode() }'''

new1 = '''    companion object {
        private const val TAG = "BackScreenNotif"
        private const val LUX_THRESHOLD = 5.0f
        private const val AOD_DELAY_MS = 8000L
        private const val SLEEP_TIMEOUT_MS = 300_000L
    }

    private var renderView: NotificationRenderView? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var isInAodMode = false
    private var dismissHandler = Handler(Looper.getMainLooper())
    private var displayDurationMs = 10000L
    private var sensorManager: android.hardware.SensorManager? = null
    private var lastLux = -1f
    private var darkSinceMs = 0L
    private val sensorListener = object : android.hardware.SensorEventListener {
        override fun onSensorChanged(event: android.hardware.SensorEvent) {
            val lux = event.values[0]; lastLux = lux
            if (lux < LUX_THRESHOLD) {
                if (darkSinceMs == 0L) darkSinceMs = System.currentTimeMillis()
                val dur = System.currentTimeMillis() - darkSinceMs
                if (dur >= SLEEP_TIMEOUT_MS && !isFinishing) { finish()
                } else if (dur >= AOD_DELAY_MS && !isInAodMode) { enterAodMode() }
            } else {
                if (isInAodMode) exitAodMode(); darkSinceMs = 0L
            }
        }
        override fun onAccuracyChanged(s: android.hardware.Sensor?, a: Int) {}
    }'''

content = content.replace(old1, new1, 1)

# 2. Replace timer with sensor registration
old2 = ("            // \u2500\u2500 5\u79d2\u540e\u8fdb\u5165 AOD \u6a21\u5f0f\uff08\u964d\u4f4e\u4eae\u5ea6\u4f46\u4ecd\u4fdd\u6301\u901a\u77e5\u5185\u5bb9\uff09 \u2500\u2500\n"
        "            dismissHandler.postDelayed(aodTransitionRunnable, AOD_TRANSITION_DELAY_MS)")
new2 = "            // \u2500\u2500 \u6ce8\u518c\u5149\u7ebf\u4f20\u611f\u5668\uff08\u5b98\u65b9\u7b97\u6cd5: lux \u9608\u503c\u63a7\u5236 AOD/\u606f\u5c4f\uff09 \u2500\u2500\n            registerLightSensor()"
content = content.replace(old2, new2, 1)

# 3. Replace enterAodMode + add new methods
old3 = '''    /** \u8fdb\u5165 AOD \u6a21\u5f0f\uff1a\u964d\u4f4e\u4eae\u5ea6\u81f3 AOD \u6c34\u5e73\uff0c\u4fdd\u7559\u901a\u77e5\u5185\u5bb9\u53ef\u89c1 */
    private fun enterAodMode() {
        if (isInAodMode) return
        isInAodMode = true
        Log.d(TAG, "Entering AOD mode (dim + keep notification)")
        try {
            // \u964d\u4f4e\u4eae\u5ea6\u5230 AOD \u6c34\u5e73\uff08~10%\uff09
            window.attributes = window.attributes.apply {
                screenBrightness = 0.05f
            }
            // \u91ca\u653e\u5524\u9192\u9501\uff0c\u8ba9\u7cfb\u7edf\u53ef\u4ee5\u7ba1\u7406\u5c4f\u5e55
            try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
            // \u4f46\u4fdd\u7559 KEEP_SCREEN_ON \u9632\u6b62\u5c4f\u5e55\u5173\u95ed\uff0c\u53ea\u4e3a AOD \u72b6\u6001
            // \u901a\u77e5\u5185\u5bb9\u6301\u7eed\u53ef\u89c1
        } catch (e: Exception) {
            Log.w(TAG, "AOD transition failed: ${e.message}")
        }
    }'''

new3 = '''    private fun enterAodMode() {
        if (isInAodMode) return; isInAodMode = true
        Log.d(TAG, "AOD (lux=$lastLux, dark=${System.currentTimeMillis()-darkSinceMs}ms)")
        try { window.attributes = window.attributes.apply { screenBrightness = 0.05f } }
        catch (e: Exception) { Log.w(TAG, "AOD enter failed: ${e.message}") }
    }
    private fun exitAodMode() {
        if (!isInAodMode) return; isInAodMode = false
        Log.d(TAG, "Exit AOD (lux=$lastLux)")
        try { window.attributes = window.attributes.apply { screenBrightness = -1.0f } }
        catch (e: Exception) { Log.w(TAG, "AOD exit failed: ${e.message}") }
    }
    private fun registerLightSensor() {
        try {
            sensorManager = getSystemService(android.content.Context.SENSOR_SERVICE) as android.hardware.SensorManager
            val ls = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_LIGHT)
            if (ls != null) {
                sensorManager?.registerListener(sensorListener, ls, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
                Log.d(TAG, "Light sensor registered")
            } else {
                Log.w(TAG, "No light sensor, 8s timer fallback")
                dismissHandler.postDelayed({ if (!isInAodMode) enterAodMode() }, 8000)
            }
        } catch (e: Exception) { Log.w(TAG, "Sensor failed: ${e.message}") }
    }'''

content = content.replace(old3, new3, 1)

# 4. Update onDestroy
old4 = '''    override fun onDestroy() {
        dismissHandler.removeCallbacksAndMessages(null)
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }'''

new4 = '''    override fun onDestroy() {
        dismissHandler.removeCallbacksAndMessages(null)
        try {
            sensorManager?.unregisterListener(sensorListener)
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {}
        Log.d(TAG, "onDestroy (lastLux=$lastLux)")
        super.onDestroy()
    }'''

content = content.replace(old4, new4, 1)

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'w', encoding='utf-8') as f:
    f.write(content)

print('Sensor-based AOD implemented')

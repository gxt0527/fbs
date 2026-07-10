import re

with open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''    private fun enterAodMode() {
        if (isInAodMode) return; isInAodMode = true
        Log.d(TAG, "Enter AOD (lux=$lastLux, dark=${System.currentTimeMillis()-darkSinceMs}ms)")
        updateAodBrightness(lastLux)
    }
    private fun exitAodMode() {
        if (!isInAodMode) return; isInAodMode = false
        Log.d(TAG, "Exit AOD (lux=$lastLux)")
        try { window.attributes = window.attributes.apply { screenBrightness = -1.0f } }
        catch (e: Exception) { Log.w(TAG, "AOD exit failed: ${e.message}") }
    }
    /** AOD \u4eae\u5ea6\u968f\u73af\u5883\u5149\u81ea\u9002\u5e94: \u5b8c\u5168\u9ed1\u6697 2%, \u63a5\u8fd1\u9608\u503c 15% */
    private fun updateAodBrightness(lux: Float) {
        if (!isInAodMode) return
        val ratio = (lux / LUX_THRESHOLD).coerceIn(0f, 1f)
        val brightness = 0.02f + ratio * 0.13f  # 2% ~ 15%
        try { window.attributes = window.attributes.apply { screenBrightness = brightness } }
        catch (e: Exception) { Log.w(TAG, "AOD brightness update failed: ${e.message}") }
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

new = '''    private fun enterAodMode() {
        if (isInAodMode) return; isInAodMode = true
        Log.d(TAG, "Enter AOD (lux=$lastLux far=$isUserFar)")
        recalcAodBrightness()
    }
    private fun exitAodMode() {
        if (!isInAodMode) return; isInAodMode = false; isMinBrightness = false
        Log.d(TAG, "Exit AOD (lux=$lastLux)")
        try { window.attributes = window.attributes.apply { screenBrightness = -1.0f } }
        catch (e: Exception) { Log.w(TAG, "AOD exit failed: ${e.message}") }
    }

    private fun onLightChanged(lux: Float) {
        lastLux = lux
        if (lux < LUX_THRESHOLD) {
            if (darkSinceMs == 0L) darkSinceMs = System.currentTimeMillis()
            val dur = System.currentTimeMillis() - darkSinceMs
            if (dur >= AOD_DELAY_MS && !isInAodMode) enterAodMode()
            else if (isInAodMode) recalcAodBrightness()
        } else {
            if (isInAodMode && isUserFar) recalcAodBrightness()
            else if (isInAodMode) exitAodMode()
            darkSinceMs = 0L
        }
    }
    private fun onProximityChanged(value: Float) {
        val maxRng = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_PROXIMITY)?.maximumRange ?: 5f
        val nowFar = value >= maxRng
        if (nowFar != isUserFar) {
            isUserFar = nowFar; farSinceMs = if (nowFar) System.currentTimeMillis() else 0L
            Log.d(TAG, "Proximity: ${if (nowFar) "FAR" else "NEAR"} v=$value")
            if (!nowFar) { coverSinceMs = System.currentTimeMillis(); isMinBrightness = false }
            if (isInAodMode) recalcAodBrightness()
        }
    }
    private fun recalcAodBrightness() {
        if (!isInAodMode) return
        val coveredMs = if (coverSinceMs > 0L) System.currentTimeMillis() - coverSinceMs else 0L
        val forceMin = !isUserFar && coveredMs >= COVER_THRESHOLD_MS
        if (forceMin) {
            if (!isMinBrightness) { isMinBrightness = true
                Log.d(TAG, "Min AOD (covered ${coveredMs/1000}s)") }
            setAodBrightness(MIN_AOD_BRIGHTNESS)
        } else if (!isUserFar) {
            val ratio = (lastLux / LUX_THRESHOLD).coerceIn(0f, 1f)
            setAodBrightness(MIN_AOD_BRIGHTNESS + ratio * (MAX_AOD_BRIGHTNESS - MIN_AOD_BRIGHTNESS))
        } else {
            isMinBrightness = false
            setAodBrightness(MIN_AOD_BRIGHTNESS)
        }
    }
    private fun setAodBrightness(b: Float) {
        try { window.attributes = window.attributes.apply { screenBrightness = b } }
        catch (e: Exception) { Log.w(TAG, "AOD brightness set failed: ${e.message}") }
    }
    private fun registerLightSensor() {
        try {
            sensorManager = getSystemService(android.content.Context.SENSOR_SERVICE) as android.hardware.SensorManager
            val ls = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_LIGHT)
            if (ls != null) sensorManager?.registerListener(sensorListener, ls, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
            else { Log.w(TAG, "No light sensor"); dismissHandler.postDelayed({ if (!isInAodMode) enterAodMode() }, 8000) }
            val ps = sensorManager?.getDefaultSensor(android.hardware.Sensor.TYPE_PROXIMITY)
            if (ps != null) sensorManager?.registerListener(sensorListener, ps, android.hardware.SensorManager.SENSOR_DELAY_NORMAL)
            Log.d(TAG, "Sensors: light=${ls!=null} prox=${ps!=null}")
        } catch (e: Exception) { Log.w(TAG, "Sensor failed: ${e.message}") }
    }'''

content = content.replace(old, new, 1)
out = open(r'E:\MSRR\fbs\android\app\src\main\kotlin\com\example\fbs\service\BackScreenNotificationActivity.kt', 'w', encoding='utf-8')
out.write(content)
out.close()
print('Done')

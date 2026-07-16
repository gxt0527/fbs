package com.example.fbs.hyperisland

import android.os.IBinder
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Shizuku UserService：阻断/恢复 XMSF 网络连接。
 *
 * 完全复刻自 NexioSchedule (课程表) 的 PrivilegedServiceImpl.setPackageNetworkingEnabled()
 * 使用 IConnectivityManager（服务名 "connectivity"）的防火墙方法。
 *
 * 关键参数：
 * - FIREWALL_CHAIN_OEM_DENY = 9（Int 常量，不是 String）
 * - setFirewallChainEnabled(int, boolean)
 * - setUidFirewallRule(int, int, int)
 * - ALLOW = 0, DENY = 2
 */
class NetworkBypassService : com.example.fbs.INetworkBypass.Stub() {

    companion object {
        private const val TAG = "HITest/Bypass"
        private const val FIREWALL_CHAIN_OEM_DENY = 9
        private const val XMSF_UID = 10215
        private const val ALLOW = 0
        private const val DENY = 2
        private const val TIMEOUT_SECONDS = 3L

        private var connectivityObj: Any? = null
    }

    override fun disableXmsfNetworking(): Boolean {
        return setXmsfNetworking(false)
    }

    override fun enableXmsfNetworking(): Boolean {
        return setXmsfNetworking(true)
    }

    override fun isReady(): Boolean = true

    /** 统一入口：enabled=true 恢复，false 阻断 */
    private fun setXmsfNetworking(enabled: Boolean): Boolean {
        val latch = CountDownLatch(1)
        var result = false

        val thread = Thread {
            try {
                val connMgr = getConnectivityManager()
                Log.i(TAG, "==== 设置 XMSF 网络: enabled=$enabled ====")

                // 启用防火墙链
                val setChainMethod = connMgr.javaClass.getMethod(
                    "setFirewallChainEnabled",
                    Int::class.javaPrimitiveType,
                    Boolean::class.javaPrimitiveType
                )
                setChainMethod.invoke(connMgr, FIREWALL_CHAIN_OEM_DENY, true)
                Log.i(TAG, "✅ setFirewallChainEnabled($FIREWALL_CHAIN_OEM_DENY, true)")

                // 设置 UID 规则
                val rule = if (enabled) ALLOW else DENY
                val setRuleMethod = connMgr.javaClass.getMethod(
                    "setUidFirewallRule",
                    Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType,
                    Int::class.javaPrimitiveType
                )
                setRuleMethod.invoke(connMgr, FIREWALL_CHAIN_OEM_DENY, XMSF_UID, rule)
                Log.i(TAG, "✅ setUidFirewallRule($FIREWALL_CHAIN_OEM_DENY, $XMSF_UID, $rule)")

                // 如果恢复网络，禁用防火墙链
                if (enabled) {
                    setChainMethod.invoke(connMgr, FIREWALL_CHAIN_OEM_DENY, false)
                    Log.i(TAG, "✅ setFirewallChainEnabled($FIREWALL_CHAIN_OEM_DENY, false)")
                }

                result = true
                Log.i(TAG, "==== 操作成功: enabled=$enabled ====")
            } catch (e: Exception) {
                Log.e(TAG, "操作失败: enabled=$enabled", e)
                result = false
            } finally {
                latch.countDown()
            }
        }

        thread.start()
        return try {
            val completed = latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            if (!completed) {
                thread.interrupt()
                Log.w(TAG, "操作超时")
                false
            } else result
        } catch (e: Exception) {
            Log.e(TAG, "等待异常", e)
            false
        }
    }

    /** 获取 IConnectivityManager 接口 */
    private fun getConnectivityManager(): Any {
        if (connectivityObj != null) return connectivityObj!!
        val smClass = Class.forName("android.os.ServiceManager")
        val getService = smClass.getMethod("getService", String::class.java)
        val rawBinder = getService.invoke(null, "connectivity") as IBinder
        Log.i(TAG, "connectivity Binder: $rawBinder")

        val stubClass = Class.forName("android.net.IConnectivityManager\$Stub")
        val asInterface = stubClass.getMethod("asInterface", IBinder::class.java)
        val obj = asInterface.invoke(null, rawBinder)
        connectivityObj = obj
        return obj
    }
}

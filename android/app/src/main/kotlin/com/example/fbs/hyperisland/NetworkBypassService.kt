package com.example.fbs.hyperisland

import android.os.IBinder
import android.os.Parcel
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Shizuku UserService：阻断/恢复 XMSF 网络连接。
 *
 * 完全复刻自 NexioSchedule (课程表) 的 PrivilegedServiceImpl.setPackageNetworkingEnabled()
 * 使用 IConnectivityManager（服务名 "connectivity"）的防火墙方法。
 *
 * ⚠️ 关键修复（2026-07-18）：
 * 原实现用 `connMgr.javaClass.getMethod("setFirewallChainEnabled", ...).invoke(...)` 反射调用
 * `@hide` 隐藏 API。debug 版（debuggable）放宽了「非 SDK 接口限制」，反射成功；
 * 但 release 版（非 debuggable）强制黑名单，反射抛 NoSuchMethodException → 防火墙不生效 → 上岛失败。
 *
 * 改用原始 `IBinder.transact()` 直接走 IPC，完全不触碰隐藏 API 的 Java 反射，
 * 在 debug 与 release 下行为一致。
 *
 * 本机（HyperOS / Android 16）IConnectivityManager 事务码（已用 app_process 实测）：
 * - TRANSACTION_setFirewallChainEnabled = 85
 * - TRANSACTION_setUidFirewallRule     = 83
 * 接口描述符（writeInterfaceToken）："android.net.IConnectivityManager"
 */
class NetworkBypassService : com.example.fbs.INetworkBypass.Stub() {

    companion object {
        private const val TAG = "HITest/Bypass"
        private const val FIREWALL_CHAIN_OEM_DENY = 9
        private const val XMSF_UID = 10215
        private const val ALLOW = 0
        private const val DENY = 2
        private const val TIMEOUT_SECONDS = 3L

        // IConnectivityManager 接口描述符
        private const val DESCRIPTOR = "android.net.IConnectivityManager"

        // 本机实测事务码（见类注释）
        private const val TRANSACTION_SET_FIREWALL_CHAIN_ENABLED = 85
        private const val TRANSACTION_SET_UID_FIREWALL_RULE = 83

        @Volatile
        private var connectivityBinder: IBinder? = null
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
                val binder = getConnectivityBinder()
                Log.i(TAG, "==== 设置 XMSF 网络: enabled=$enabled ====")

                // 启用防火墙链 setFirewallChainEnabled(int chain, boolean enable)
                transactSetFirewallChainEnabled(binder, FIREWALL_CHAIN_OEM_DENY, true)
                Log.i(TAG, "✅ setFirewallChainEnabled($FIREWALL_CHAIN_OEM_DENY, true)")

                // 设置 UID 规则 setUidFirewallRule(int chain, int uid, int rule)
                val rule = if (enabled) ALLOW else DENY
                transactSetUidFirewallRule(binder, FIREWALL_CHAIN_OEM_DENY, XMSF_UID, rule)
                Log.i(TAG, "✅ setUidFirewallRule($FIREWALL_CHAIN_OEM_DENY, $XMSF_UID, $rule)")

                // 如果恢复网络，禁用防火墙链
                if (enabled) {
                    transactSetFirewallChainEnabled(binder, FIREWALL_CHAIN_OEM_DENY, false)
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

    // ── 原始 Binder 事务（不依赖任何隐藏 API 反射）──

    private fun transactSetFirewallChainEnabled(binder: IBinder, chain: Int, enable: Boolean) {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(DESCRIPTOR)
            data.writeInt(chain)
            data.writeInt(if (enable) 1 else 0)
            binder.transact(TRANSACTION_SET_FIREWALL_CHAIN_ENABLED, data, reply, 0)
            reply.readException()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private fun transactSetUidFirewallRule(binder: IBinder, chain: Int, uid: Int, rule: Int) {
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(DESCRIPTOR)
            data.writeInt(chain)
            data.writeInt(uid)
            data.writeInt(rule)
            binder.transact(TRANSACTION_SET_UID_FIREWALL_RULE, data, reply, 0)
            reply.readException()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    /** 获取 connectivity 原始 IBinder（ServiceManager.getService 为 greylist，release 可用） */
    private fun getConnectivityBinder(): IBinder {
        connectivityBinder?.let { return it }
        val smClass = Class.forName("android.os.ServiceManager")
        val getService = smClass.getMethod("getService", String::class.java)
        val rawBinder = getService.invoke(null, "connectivity") as IBinder
        Log.i(TAG, "connectivity Binder: $rawBinder")
        connectivityBinder = rawBinder
        return rawBinder
    }
}

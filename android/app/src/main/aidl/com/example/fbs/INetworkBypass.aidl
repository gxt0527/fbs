// INetworkBypass.aidl
package com.example.fbs;

interface INetworkBypass {
    /**
     * 阻断 XMSF (com.xiaomi.xmsf) 网络连接。
     * 通过 INetworkManagementService.setUidFirewallRule 设置防火墙规则，
     * 使 XMSF 无法联网 → 焦点通知鉴权请求超时 → FocusPlugin 回退放行。
     * @return true 表示成功
     */
    boolean disableXmsfNetworking();

    /**
     * 恢复 XMSF 网络连接。
     * @return true 表示成功
     */
    boolean enableXmsfNetworking();

    /**
     * 检查服务是否就绪。
     */
    boolean isReady();
}

# Shizuku UserService / AIDL Stub keep 规则
#
# 这两个包/类通过反射 + 进程间 Binder 启动，不在 AndroidManifest 中静态声明。
# R8 静态分析看不到引用，会整类删除，导致 release 包 ClassNotFoundException。
# 这是 FBS 在 release release debug 差异的真正原因。
# debug 包默认禁 minify，所以正常。

# 超级岛相关：阻断服务 + Json 转发器 + 测试桩
-keep class com.example.fbs.hyperisland.** { *; }

# AIDL 生成的 Stub/Proxy 接口
-keep class com.example.fbs.INetworkBypass { *; }
-keep class com.example.fbs.INetworkBypass$Stub { *; }
-keep class com.example.fbs.INetworkBypass$Stub$Proxy { *; }

# Shizuku API 内部使用 ServiceManager.getService 反射启动 UserService，
# 所有 UserService 子类都需要保留类名 + 公参构造器
-keep class * extends android.os.IBinder {
    public <init>(...);
}
-keepclassmembers class * extends android.os.IBinder {
    public <init>(...);
}

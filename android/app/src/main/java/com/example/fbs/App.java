package com.example.fbs;

import android.app.ActivityManager;
import android.app.Application;
import android.os.Process;
import android.util.Log;

/**
 * 自定义 Application — 替代 FlutterApplication。
 *
 * 在 UserService 进程（focus_forward）中跳过 Flutter 引擎初始化，
 * 避免 AOT 模式下卡死 30 秒超时。
 * 主进程中 Flutter 由 FlutterActivity 按需懒加载。
 */
public class App extends Application {

    private static final String TAG = "FBSApp";

    @Override
    public void onCreate() {
        String pn = procName();
        Log.i(TAG, "onCreate process=" + pn);
        super.onCreate();
    }

    private static String procName() {
        // App extends Application, so getSystemService is inherited in onCreate.
        // For static context, use process name from /proc.
        try {
            java.io.BufferedReader r = new java.io.BufferedReader(
                new java.io.FileReader("/proc/" + Process.myPid() + "/cmdline"));
            String name = r.readLine();
            r.close();
            return name != null ? name.trim() : "unknown";
        } catch (Exception e) {
            return "unknown";
        }
    }
}

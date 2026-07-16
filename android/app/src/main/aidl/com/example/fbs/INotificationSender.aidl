// INotificationSender.aidl
package com.example.fbs;

interface INotificationSender {
    /**
     * 在 Shizuku 进程中发送焦点通知
     * @param jsonParam miui.focus.param JSON 字符串
     * @param notificationId 通知 ID
     * @param title 通知标题
     * @param text 通知正文
     */
    void sendFocusNotification(String jsonParam, int notificationId, String title, String text);

    /**
     * 检查是否就绪
     */
    boolean isReady();
}

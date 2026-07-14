package com.example.fbs.service;

import com.xzakota.hyper.notification.island.model.TextInfo;

/**
 * 辅助 TextInfo 赋值（绕过 Kotlin AAR 跨版本 setter 不可访问问题）
 */
public class TextInfoHelper {
    public static TextInfo createTextInfo(String title, String content) {
        TextInfo info = new TextInfo();
        info.setTitle(title);
        info.setContent(content);
        return info;
    }
}

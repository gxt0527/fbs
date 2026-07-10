import 'package:flutter/material.dart';
import '../models/notification_item.dart';
import '../main.dart';

class NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onForward;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.notification,
    this.onForward,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GlassTokens.radiusLG),
              gradient: GlassTokens.glassGradient(Theme.of(context).brightness),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.30),
                width: 0.5,
              ),
              boxShadow: GlassTokens.glassShadow(Theme.of(context).brightness),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(GlassTokens.radiusXS),
                        color: notification.isFocusNotification
                            ? const Color(0xFFFF9500).withValues(alpha: 0.12)
                            : GlassTokens.accent.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        notification.isFocusNotification
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_rounded,
                        size: 16,
                        color: notification.isFocusNotification
                            ? const Color(0xFFFF9500)
                            : GlassTokens.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        notification.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (notification.typeLabel.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: notification.isOngoing
                              ? const Color(0xFF34C759).withValues(alpha: 0.10)
                              : GlassTokens.accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(GlassTokens.radiusFull),
                        ),
                        child: Text(
                          notification.typeLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: notification.isOngoing ? const Color(0xFF34C759) : GlassTokens.accent,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      notification.displayTime,
                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  ],
                ),
                if (notification.content.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    notification.content,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.phone_android, size: 12, color: isDark ? Colors.white24 : Colors.black26),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        notification.displayAppName,
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white30 : Colors.black38),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onForward != null)
                      _glassIconButton(Icons.send_rounded, '发送到背屏', onForward!),
                    if (onDelete != null)
                      _glassIconButton(Icons.delete_outline_rounded, '删除', onDelete!),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _glassIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusXS),
          color: GlassTokens.accent.withValues(alpha: 0.08),
        ),
        child: Icon(icon, size: 15, color: GlassTokens.accent),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../main.dart';

class StatusIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEnabled;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.icon,
    required this.label,
    required this.isEnabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isEnabled ? const Color(0xFF34C759) : const Color(0xFFFF375F);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(GlassTokens.radiusSM),
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.35),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.22),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

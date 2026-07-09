class NotificationItem {
  final String title;
  final String content;
  final String packageName;
  final String appName;
  final String category;
  final DateTime timestamp;
  final bool isFocusNotification;
  final bool isOngoing;
  final int notificationId;
  final String groupKey;
  final String channelId;
  final String subText;
  final String bigText;
  final String notificationKey;

  NotificationItem({
    required this.title,
    required this.content,
    required this.packageName,
    this.appName = '',
    this.category = '',
    required this.timestamp,
    this.isFocusNotification = false,
    this.isOngoing = false,
    this.notificationId = 0,
    this.groupKey = '',
    this.channelId = '',
    this.subText = '',
    this.bigText = '',
    this.notificationKey = '',
  });

  factory NotificationItem.fromMap(Map<dynamic, dynamic> map) {
    return NotificationItem(
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      packageName: map['packageName'] ?? '',
      appName: map['appName'] ?? '',
      category: map['category'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
      isFocusNotification: map['isFocusNotification'] ?? false,
      isOngoing: map['isOngoing'] ?? false,
      notificationId: map['notificationId'] ?? 0,
      groupKey: map['groupKey'] ?? '',
      channelId: map['channelId'] ?? '',
      subText: map['subText'] ?? '',
      bigText: map['bigText'] ?? '',
      notificationKey: map['notificationKey'] ?? '',
    );
  }

  /// 显示的标题（优先用通知标题，回退到应用名）
  String get displayTitle {
    if (title.isNotEmpty) return title;
    if (appName.isNotEmpty) return appName;
    return _getAppNameFromPackage(packageName);
  }

  /// 显示的副标题
  String get displaySubtitle {
    final parts = <String>[];
    if (subText.isNotEmpty) parts.add(subText);
    if (category.isNotEmpty) parts.add('[$category]');
    if (isOngoing) parts.add('[持续]');
    return parts.join(' ');
  }

  /// 类型标签（用于 UI 展示）
  String get typeLabel {
    if (isOngoing) return '实时动态';
    if (channelId.isNotEmpty) return channelId.split('_').last;
    return '';
  }

  String get displayTime {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  /// 显示的应用名（优先用系统返回的 appName）
  String get displayAppName {
    if (appName.isNotEmpty) return appName;
    return _getAppNameFromPackage(packageName);
  }

  String _getAppNameFromPackage(String pkg) {
    switch (pkg) {
      case 'com.tencent.mm':
        return '微信';
      case 'com.tencent.mobileqq':
        return 'QQ';
      case 'com.ss.android.ugc.aweme':
        return '抖音';
      case 'com.taobao.taobao':
        return '淘宝';
      case 'com.eg.android.AlipayGphone':
        return '支付宝';
      case 'com.sina.weibo':
        return '微博';
      case 'com.netease.mail':
        return '网易邮箱';
      case 'com.android.phone':
        return '电话';
      case 'com.android.mms':
        return '短信';
      case 'com.xiaomi.subscreencenter':
        return '背屏中心';
      default:
        return pkg.split('.').last;
    }
  }
}

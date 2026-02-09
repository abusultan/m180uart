import 'package:flutter/foundation.dart';

class RepNotification {
  final String title;
  final String body;
  final String time;

  const RepNotification({
    required this.title,
    required this.body,
    required this.time,
  });
}

class RepStore {
  static final ValueNotifier<List<RepNotification>> notifications =
      ValueNotifier<List<RepNotification>>([
    const RepNotification(
      title: 'طلب جديد',
      body: 'أحمد صالح قام بإرسال طلب جديد.',
      time: 'قبل 5 دقائق',
    ),
    const RepNotification(
      title: 'تحديث طلب',
      body: 'طلب ORD-1002 تم تجهيزه.',
      time: 'قبل 30 دقيقة',
    ),
  ]);

  static final Set<String> _lowStockNotified = <String>{};

  static void addLowStockNotification({
    required String orderId,
    required String customer,
    required List<String> missingItems,
  }) {
    if (_lowStockNotified.contains(orderId)) return;
    _lowStockNotified.add(orderId);

    final body =
        'الطلب $orderId للزبون $customer يحتاج تعزيز: ${missingItems.join('، ')}';

    notifications.value = [
      RepNotification(
        title: 'تنبيه مخزون',
        body: body,
        time: 'الآن',
      ),
      ...notifications.value,
    ];
  }
}

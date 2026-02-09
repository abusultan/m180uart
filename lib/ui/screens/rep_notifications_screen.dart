import 'package:flutter/material.dart';

class RepNotificationsScreen extends StatelessWidget {
  const RepNotificationsScreen({super.key});

  static const List<_MockNotification> _items = [
    _MockNotification(
      title: 'طلب جديد',
      body: 'أحمد صالح قام بإرسال طلب جديد.',
      time: 'قبل 5 دقائق',
    ),
    _MockNotification(
      title: 'تحديث طلب',
      body: 'طلب ORD-1002 تم تجهيزه.',
      time: 'قبل 30 دقيقة',
    ),
    _MockNotification(
      title: 'رسالة',
      body: 'الزبون محمد علي يريد تغيير الكمية.',
      time: 'قبل ساعة',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('إشعارات الزبائن'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: Color(0xFF00FF88),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.time,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MockNotification {
  final String title;
  final String body;
  final String time;

  const _MockNotification({
    required this.title,
    required this.body,
    required this.time,
  });
}

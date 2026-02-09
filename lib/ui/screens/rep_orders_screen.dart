import 'package:flutter/material.dart';

class RepOrdersScreen extends StatefulWidget {
  const RepOrdersScreen({super.key});

  @override
  State<RepOrdersScreen> createState() => _RepOrdersScreenState();
}

class _RepOrdersScreenState extends State<RepOrdersScreen> {
  final List<_MockOrder> _orders = [
    _MockOrder(
      id: 'ORD-1001',
      customer: 'أحمد صالح',
      phone: '0790001111',
      status: 'جديد',
      total: 35.0,
    ),
    _MockOrder(
      id: 'ORD-1002',
      customer: 'محمد علي',
      phone: '0790002222',
      status: 'تم التسليم',
      total: 18.5,
    ),
    _MockOrder(
      id: 'ORD-1003',
      customer: 'سارة يوسف',
      phone: '0790003333',
      status: 'ملغي',
      total: 52.0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('طلبات الزبائن'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          final bool canDeliver = order.status == 'جديد';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.id,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: order.status == 'تم التسليم'
                            ? const Color(0xFF00FF88)
                            : order.status == 'ملغي'
                                ? Colors.redAccent
                                : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order.status,
                        style: TextStyle(
                          color: order.status == 'تم التسليم'
                              ? Colors.black
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'الزبون: ${order.customer}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  'الهاتف: ${order.phone}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  'الإجمالي: ${order.total.toStringAsFixed(2)} JOD',
                  style: const TextStyle(color: Colors.white),
                ),
                if (canDeliver) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          order.status = 'تم التسليم';
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'تم التسليم',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MockOrder {
  final String id;
  final String customer;
  final String phone;
  String status;
  final double total;

  const _MockOrder({
    required this.id,
    required this.customer,
    required this.phone,
    required this.status,
    required this.total,
  });
}

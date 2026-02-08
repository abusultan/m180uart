import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Map<String, int> _quantities = {};

  final List<_MockProduct> _products = const [
    _MockProduct(
      id: 'front_full',
      name: 'Front Full',
      imageAsset: 'assets/logo.png',
    ),
    _MockProduct(
      id: 'front_shell',
      name: 'Front Shell',
      imageAsset: 'assets/logo.png',
    ),
    _MockProduct(
      id: 'back_cover',
      name: 'Back Cover',
      imageAsset: 'assets/logo.png',
    ),
    _MockProduct(
      id: 'camera_lens',
      name: 'Camera Lens',
      imageAsset: 'assets/logo.png',
    ),
    _MockProduct(
      id: 'side',
      name: 'Side',
      imageAsset: 'assets/logo.png',
    ),
    _MockProduct(
      id: 'uv',
      name: 'UV',
      imageAsset: 'assets/logo.png',
    ),
  ];

  void _openQuantityDialog(_MockProduct product) {
    final int currentQty = _quantities[product.id] ?? 0;
    final TextEditingController controller = TextEditingController(
      text: currentQty == 0 ? '1' : currentQty.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تحديد الكمية',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              product.name,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    final int value =
                        (int.tryParse(controller.text) ?? 0) - 1;
                    controller.text = value < 0 ? '0' : value.toString();
                  },
                  icon: const Icon(Icons.remove_circle, color: Colors.grey),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final int value =
                        (int.tryParse(controller.text) ?? 0) + 1;
                    controller.text = value.toString();
                  },
                  icon: const Icon(Icons.add_circle, color: Color(0xFF00FF88)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              final int value = int.tryParse(controller.text) ?? 0;
              setState(() {
                if (value <= 0) {
                  _quantities.remove(product.id);
                } else {
                  _quantities[product.id] = value;
                }
              });
              Navigator.pop(context);
            },
            child: const Text(
              'حفظ',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  void _submitOrderMock(String customerName, String repName) {
    final List<_MockProduct> selectedProducts = _products
        .where((p) => (_quantities[p.id] ?? 0) > 0)
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تم إرسال الطلب (موكاب)',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المندوب: $repName',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              'الزبون: $customerName',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'المنتجات:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            ...selectedProducts.map(
              (p) => Text(
                '- ${p.name} (x${_quantities[p.id]})',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'إغلاق',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final String customerName = user?.name ?? '';
    final String repName = user?.representativeName ?? '';
    final bool hasItems =
        _quantities.values.any((quantity) => quantity > 0);
    final bool canSubmit =
        hasItems && customerName.isNotEmpty && repName.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('سلة المنتجات'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بيانات الطلب',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('الزبون', customerName),
                  const SizedBox(height: 8),
                  _buildInfoRow('المندوب', repName),
                  if (repName.isEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'لا يوجد مندوب مرتبط بالحساب.',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'المنتجات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                final int qty = _quantities[product.id] ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        product.imageAsset,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(
                      product.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: qty > 0
                        ? Text(
                            'الكمية: $qty',
                            style: const TextStyle(color: Colors.white70),
                          )
                        : const Text(
                            'لم يتم الإضافة',
                            style: TextStyle(color: Colors.white38),
                          ),
                    trailing: InkWell(
                      onTap: () => _openQuantityDialog(product),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00FF88),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: canSubmit
                    ? () => _submitOrderMock(customerName, repName)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canSubmit
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF2A2A2A),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'إتمام الطلب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label:',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _MockProduct {
  final String id;
  final String name;
  final String imageAsset;

  const _MockProduct({
    required this.id,
    required this.name,
    required this.imageAsset,
  });
}

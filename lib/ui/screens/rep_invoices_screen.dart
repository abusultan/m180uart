import 'package:flutter/material.dart';

class RepInvoicesScreen extends StatefulWidget {
  const RepInvoicesScreen({super.key});

  @override
  State<RepInvoicesScreen> createState() => _RepInvoicesScreenState();
}

class _RepInvoicesScreenState extends State<RepInvoicesScreen> {
  final Map<String, _InvoiceItem> _selectedItems = {};
  final TextEditingController _searchController = TextEditingController();

  _MockCustomer? _selectedCustomer;
  DateTime? _sessionStart;
  DateTime? _sessionEnd;
  String _sessionLocation = '';
  bool _loadingLocation = false;
  bool _savingInvoice = false;
  bool _savingCharge = false;

  final List<_SavedInvoice> _history = [];

  final List<_MockProduct> _products = const [
    _MockProduct(id: 'p1', name: 'Front Full'),
    _MockProduct(id: 'p2', name: 'Front Shell'),
    _MockProduct(id: 'p3', name: 'Back Cover'),
    _MockProduct(id: 'p4', name: 'Camera Lens'),
    _MockProduct(id: 'p5', name: 'Side'),
    _MockProduct(id: 'p6', name: 'UV'),
  ];

  final List<_MockCustomer> _customers = const [
    _MockCustomer(id: 'c1', name: 'أحمد صالح', phone: '0790001111'),
    _MockCustomer(id: 'c2', name: 'محمد علي', phone: '0790002222'),
    _MockCustomer(id: 'c3', name: 'سارة يوسف', phone: '0790003333'),
    _MockCustomer(id: 'c4', name: 'ليلى حسن', phone: '0790004444'),
  ];

  List<_MockCustomer> get _filteredCustomers {
    final query = _searchController.text.trim();
    if (query.isEmpty) return _customers;
    return _customers
        .where(
          (c) =>
              c.name.contains(query) ||
              c.phone.contains(query) ||
              c.id.contains(query),
        )
        .toList();
  }

  double get _total {
    double total = 0;
    for (final item in _selectedItems.values) {
      total += item.qty * item.price;
    }
    return total;
  }

  String get _sessionDuration {
    if (_sessionStart == null) return '00:00';
    final end = _sessionEnd ?? DateTime.now();
    final diff = end.difference(_sessionStart!);
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _startSession(_MockCustomer customer) {
    setState(() {
      _selectedCustomer = customer;
      _sessionStart = DateTime.now();
      _sessionEnd = null;
      _sessionLocation = '';
      _loadingLocation = false;
      _selectedItems.clear();
    });
  }

  Future<void> _selectCustomer() async {
    final _MockCustomer? customer = await showModalBottomSheet<_MockCustomer>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setModalState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'بحث عن الزبون',
                      labelStyle: TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Color(0xFF121212),
                      border: OutlineInputBorder(),
                      prefixIcon:
                          Icon(Icons.search, color: Color(0xFF00FF88)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return ListTile(
                          title: Text(
                            customer.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            customer.phone,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => Navigator.pop(context, customer),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (customer == null) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تأكيد',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'سيتم إنشاء جلسة للزبون ${customer.name}. هل تريد المتابعة؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم', style: TextStyle(color: Color(0xFF00FF88))),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _startSession(customer);
    }
  }

  void _openAddDialog(_MockProduct product) {
    final TextEditingController qtyController = TextEditingController(
      text: '1',
    );
    final TextEditingController priceController = TextEditingController(
      text: '1.0',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'إضافة منتج',
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
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'العدد',
                labelStyle: TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Color(0xFF121212),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'سعر القطعة',
                labelStyle: TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Color(0xFF121212),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text.trim()) ?? 0;
              final price = double.tryParse(priceController.text.trim()) ?? 0;
              if (qty <= 0 || price <= 0) {
                Navigator.pop(context);
                return;
              }
              setState(() {
                _selectedItems[product.id] =
                    _InvoiceItem(product: product, qty: qty, price: price);
              });
              Navigator.pop(context);
            },
            child: const Text(
              'إضافة',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAndEndSession() async {
    await _saveInvoiceInternal(chargeAccount: false);
  }

  Future<void> _saveAndCharge() async {
    if (_selectedCustomer == null) return;
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة منتجات للفاتورة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final customer = _selectedCustomer!;
    final int totalQty =
        _selectedItems.values.fold(0, (sum, item) => sum + item.qty);
    if (totalQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد عدد صالح للشحن'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'شحن رصيد',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'سوف يتم شحن رصيد ${customer.name}\n'
          'بعدد اللزقات: $totalQty',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('شحن', style: TextStyle(color: Color(0xFF00FF88))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _saveInvoiceInternal(chargeAccount: true, chargeQty: totalQty);
  }

  Future<void> _saveInvoiceInternal({
    required bool chargeAccount,
    int? chargeQty,
  }) async {
    if (_selectedCustomer == null) return;
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة منتجات للفاتورة'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      if (chargeAccount) {
        _savingCharge = true;
      } else {
        _savingInvoice = true;
      }
    });

    final customer = _selectedCustomer!;
    final start = _sessionStart ?? DateTime.now();
    final end = DateTime.now();

    final location = await _fetchLocation();
    if (location == null) {
      setState(() {
        _savingInvoice = false;
        _savingCharge = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تفعيل الموقع والسماح بالوصول قبل الحفظ'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final duration = end.difference(start);
    final durationText =
        '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    final total = _total;

    final itemsCopy = _selectedItems.values
        .map(
          (e) => _InvoiceItem(
            product: e.product,
            qty: e.qty,
            price: e.price,
          ),
        )
        .toList();

    final saved = _SavedInvoice(
      id: 'INV-${DateTime.now().millisecondsSinceEpoch}',
      customer: customer,
      start: start,
      end: end,
      location: location,
      items: itemsCopy,
      total: total,
    );

    setState(() {
      _history.insert(0, saved);
      _selectedItems.clear();
      _selectedCustomer = null;
      _sessionStart = null;
      _sessionEnd = null;
      _sessionLocation = '';
      _loadingLocation = false;
      _searchController.clear();
      _savingInvoice = false;
      _savingCharge = false;
    });

    if (chargeAccount && chargeQty != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم شحن ${chargeQty.toString()} لصالح ${customer.name} (موكاب)',
          ),
          backgroundColor: const Color(0xFF00FF88),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تم حفظ الفاتورة (موكاب)',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'الزبون: ${customer.name}\n'
          'الوقت: $durationText\n'
          'الموقع: $location\n'
          'الإجمالي: ${total.toStringAsFixed(2)} JOD'
          '${chargeAccount && chargeQty != null ? '\nتم شحن: $chargeQty لزقة' : ''}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<String?> _fetchLocation() async {
    return null;
  }

  void _exportPdfMock(_SavedInvoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تصدير PDF (موكاب)',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'تم إنشاء ملف PDF للفاتورة ${invoice.id}\nالمسار: /storage/emulated/0/Invoices/${invoice.id}.pdf',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$h:$m  $d/$mo';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('الفواتير'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E1E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectedCustomer == null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _selectCustomer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'اختيار الزبون',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'جلسة مع: ${_selectedCustomer!.name}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الوقت: $_sessionDuration',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _loadingLocation
                        ? 'جاري تحديد الموقع...'
                        : 'الموقع: سيتم حفظه عند الإنهاء',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'المنتجات',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ..._products.map((product) {
                  final item = _selectedItems[product.id];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        product.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: item == null
                          ? const Text(
                              'لم يتم الإضافة',
                              style: TextStyle(color: Colors.white38),
                            )
                          : Text(
                              'العدد: ${item.qty} | السعر: ${item.price} JOD',
                              style: const TextStyle(color: Colors.white70),
                            ),
                      trailing: InkWell(
                        onTap: _selectedCustomer == null
                            ? null
                            : () => _openAddDialog(product),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _selectedCustomer == null
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xFF00FF88),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Colors.black),
                        ),
                      ),
                    ),
                  );
                }).toList(),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'الفواتير السابقة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._history.map((invoice) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            invoice.id,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'الزبون: ${invoice.customer.name}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الوقت: ${_formatDateTime(invoice.start)} - ${_formatDateTime(invoice.end)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الموقع: ${invoice.location}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'الإجمالي: ${invoice.total.toStringAsFixed(2)} JOD',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () => _exportPdfMock(invoice),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00FF88),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('تصدير PDF'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي',
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      '${_total.toStringAsFixed(2)} JOD',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedItems.isEmpty ||
                                  _selectedCustomer == null
                              ? null
                              : _saveAndEndSession,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _savingInvoice
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'حفظ',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedItems.isEmpty ||
                                  _selectedCustomer == null
                              ? null
                              : _saveAndCharge,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF88),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _savingCharge
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Text(
                                  'حفظ مع شحن',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockProduct {
  final String id;
  final String name;

  const _MockProduct({required this.id, required this.name});
}

class _InvoiceItem {
  final _MockProduct product;
  final int qty;
  final double price;

  const _InvoiceItem({
    required this.product,
    required this.qty,
    required this.price,
  });
}

class _MockCustomer {
  final String id;
  final String name;
  final String phone;

  const _MockCustomer({
    required this.id,
    required this.name,
    required this.phone,
  });
}

class _SavedInvoice {
  final String id;
  final _MockCustomer customer;
  final DateTime start;
  final DateTime end;
  final String location;
  final List<_InvoiceItem> items;
  final double total;

  const _SavedInvoice({
    required this.id,
    required this.customer,
    required this.start,
    required this.end,
    required this.location,
    required this.items,
    required this.total,
  });
}

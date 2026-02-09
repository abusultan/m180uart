import 'package:flutter/material.dart';
import '../../core/app_strings.dart';
import '../../data/models/product_models.dart';
import '../../services/api_service.dart';

class GoodDetailScreen extends StatefulWidget {
  final int goodId;

  const GoodDetailScreen({super.key, required this.goodId});

  @override
  State<GoodDetailScreen> createState() => _GoodDetailScreenState();
}

class _GoodDetailScreenState extends State<GoodDetailScreen> {
  Good? _good;
  bool _isLoading = true;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _loadGoodDetails();
  }

  Future<void> _loadGoodDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final good = await ApiService().getGoodById(widget.goodId);
      if (mounted) {
        setState(() {
          _good = good;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading good details: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showAddToCartDialog() async {
    if (_good == null) return;

    setState(() => _isLoading = true);
    final response = await ApiService().addToCart(_good!.id, _quantity);
    setState(() => _isLoading = false);

    if (mounted) {
      if (response != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(
              AppStrings.of(context, 'added_to_cart'),
              style: const TextStyle(color: Colors.white),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _good!.nameAr.isNotEmpty ? _good!.nameAr : _good!.nameEn,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  '${AppStrings.of(context, 'quantity')}: $_quantity',
                  style: const TextStyle(color: Color(0xFF00FF88)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // إغلاق الحوار
                  Navigator.pop(
                    context,
                    true,
                  ); // العودة للشاشة السابقة مع إشارة نجاح
                },
                child: Text(
                  AppStrings.of(context, 'ok'),
                  style: const TextStyle(color: Color(0xFF00FF88)),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context, 'add_to_cart_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(AppStrings.of(context, 'product_details')),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00FF88)),
            )
          : _good == null
          ? Center(
              child: Text(
                AppStrings.of(context, 'product_not_found'),
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صورة المنتج
                  Container(
                    width: double.infinity,
                    height: 300,
                    color: const Color(0xFF1E1E1E),
                    child: _good!.image.isNotEmpty
                        ? Image.network(
                            _good!.image,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                  size: 80,
                                ),
                              );
                            },
                          )
                        : const Center(
                            child: Icon(
                              Icons.shopping_bag,
                              color: Colors.grey,
                              size: 80,
                            ),
                          ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // اسم المنتج
                        Text(
                          _good!.nameAr.isNotEmpty
                              ? _good!.nameAr
                              : _good!.nameEn,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_good!.nameAr.isNotEmpty &&
                            _good!.nameEn.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _good!.nameEn,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                            ),
                          ),

                        const SizedBox(height: 16),

                        // السعر
                        Row(
                          children: [
                            if (_good!.priceAfterDiscount != null) ...[
                              Text(
                                '${_good!.price} ${AppStrings.of(context, 'currency_jod')}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 18,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_good!.priceAfterDiscount} ${AppStrings.of(context, 'currency_jod')}',
                                style: const TextStyle(
                                  color: Color(0xFF00FF88),
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${_calculateDiscount()}% ${AppStrings.of(context, 'discount')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ] else
                              Text(
                                '${_good!.price} ${AppStrings.of(context, 'currency_jod')}',
                                style: const TextStyle(
                                  color: Color(0xFF00FF88),
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // معلومات المخزون
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.inventory_2,
                                color: Color(0xFF00FF88),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.of(context, 'available_stock'),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_good!.stock} ${AppStrings.of(context, 'pieces')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _good!.stock > 0
                                      ? const Color(0xFF00FF88).withOpacity(0.2)
                                      : Colors.redAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _good!.stock > 0
                                        ? const Color(0xFF00FF88)
                                        : Colors.redAccent,
                                  ),
                                ),
                                child: Text(
                                  _good!.stock > 0
                                      ? AppStrings.of(context, 'available')
                                      : AppStrings.of(context, 'out_of_stock'),
                                  style: TextStyle(
                                    color: _good!.stock > 0
                                        ? const Color(0xFF00FF88)
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // الوصف
                        if (_good!.descriptionAr != null ||
                            _good!.descriptionEn != null) ...[
                          Text(
                            AppStrings.of(context, 'description'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _good!.descriptionAr ??
                                  _good!.descriptionEn ??
                                  '',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // اختيار الكمية
                        Text(
                          AppStrings.of(context, 'quantity'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: _quantity > 1
                                    ? () {
                                        setState(() {
                                          _quantity--;
                                        });
                                      }
                                    : null,
                                icon: const Icon(Icons.remove_circle),
                                color: _quantity > 1
                                    ? const Color(0xFF00FF88)
                                    : Colors.grey,
                                iconSize: 32,
                              ),
                              const SizedBox(width: 24),
                              Text(
                                '$_quantity',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 24),
                              IconButton(
                                onPressed: _quantity < _good!.stock
                                    ? () {
                                        setState(() {
                                          _quantity++;
                                        });
                                      }
                                    : null,
                                icon: const Icon(Icons.add_circle),
                                color: _quantity < _good!.stock
                                    ? const Color(0xFF00FF88)
                                    : Colors.grey,
                                iconSize: 32,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // زر الإضافة للسلة
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _good!.stock > 0
                                ? _showAddToCartDialog
                                : null,
                            icon: const Icon(Icons.shopping_cart),
                            label: Text(
                              _good!.stock > 0
                                  ? AppStrings.of(context, 'add_to_cart')
                                  : AppStrings.of(context, 'out_of_stock'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _good!.stock > 0
                                  ? const Color(0xFF00FF88)
                                  : const Color(0xFF2A2A2A),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  int _calculateDiscount() {
    if (_good!.priceAfterDiscount == null) return 0;
    final original = double.tryParse(_good!.price) ?? 0;
    final discounted = double.tryParse(_good!.priceAfterDiscount!) ?? 0;
    if (original == 0) return 0;
    return (((original - discounted) / original) * 100).round();
  }
}

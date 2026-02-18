import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_strings.dart';
import '../../data/models/product_models.dart';
import '../../services/api_service.dart';
import 'good_detail_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Map<int, int> _quantities = {};
  List<Good> _goods = [];
  List<Good> _cartProducts = []; // قائمة المنتجات الموجودة فعلياً في السلة
  bool _isLoading = false;
  int _currentPage = 1;
  int _totalPages = 1;
  bool _hasMore = true;
  double _totalPrice = 0;

  // متغيرات البحث
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Timer? _debounce;

  String _safeUrl(String url) => ApiService().normalizeUrl(url);

  @override
  void initState() {
    super.initState();
    _loadGoods();
    _loadCart();
  }

  Future<void> _loadCart() async {
    final cartData = await ApiService().getCart();
    if (cartData != null && mounted) {
      final List items = cartData['items'] ?? [];
      final List<Good> tempCartProducts = [];

      setState(() {
        _totalPrice =
            double.tryParse(cartData['total_price']?.toString() ?? '0') ?? 0;
        _quantities.clear();
        for (var item in items) {
          final int goodId = item['good_id'];
          final int qty = item['quantity'];
          _quantities[goodId] = qty;

          if (item['good'] != null) {
            tempCartProducts.add(Good.fromJson(item['good']));
          }
        }
        _cartProducts = tempCartProducts;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadGoods() async {
    // السماح بالتحميل فقط إذا لم يكن هناك تحميل جاري
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = _searchQuery.isEmpty
          ? await ApiService().getGoods(page: _currentPage)
          : await ApiService().searchGoods(_searchQuery, page: _currentPage);

      if (response != null && mounted) {
        setState(() {
          _goods.addAll(response.data);
          _totalPages = response.lastPage;
          _hasMore = response.nextPageUrl != null;
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading goods: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _searchQuery = query;
          _goods.clear();
          _currentPage = 1;
          _hasMore = true;
        });
        _loadGoods();
      }
    });
  }

  Future<void> _refreshGoods() async {
    setState(() {
      _goods.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = false;
    });
    await _loadGoods();
    await _loadCart();
  }

  void _openQuantityDialog(Good good) {
    final int currentQty = _quantities[good.id] ?? 0;
    final TextEditingController controller = TextEditingController(
      text: currentQty == 0 ? '1' : currentQty.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(context, 'set_quantity'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              good.nameAr.isNotEmpty ? good.nameAr : good.nameEn,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              '${AppStrings.of(context, 'price')}: ${good.priceAfterDiscount ?? good.price} ${AppStrings.of(context, 'currency_jod')}',
              style: const TextStyle(color: Color(0xFF00FF88), fontSize: 14),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    final int value = (int.tryParse(controller.text) ?? 1) - 1;
                    // جعل أقل قيمة هي 1 بدلاً من 0
                    controller.text = value < 1 ? '1' : value.toString();
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
                    final int value = (int.tryParse(controller.text) ?? 0) + 1;
                    if (value <= good.stock) {
                      controller.text = value.toString();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${AppStrings.of(context, 'available_stock')}: ${good.stock}',
                          ),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_circle, color: Color(0xFF00FF88)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${AppStrings.of(context, 'stock_available')}${good.stock}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          if (currentQty > 0)
            TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                final response = await ApiService().removeFromCart(good.id);
                setState(() => _isLoading = false);

                if (mounted && response != null) {
                  await _loadCart();
                  Navigator.pop(context);
                }
              },
              child: Text(
                AppStrings.of(context, 'delete'),
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppStrings.of(context, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              final int value = int.tryParse(controller.text) ?? 1;
              if (value > good.stock) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${AppStrings.of(context, 'available_stock')}: ${good.stock}',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final response = await ApiService().updateCartQuantity(
                good.id,
                value,
              );

              if (mounted) {
                if (response != null) {
                  await _loadCart();
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppStrings.of(context, 'cart_update_failed'),
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: Text(
              AppStrings.of(context, 'save'),
              style: const TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCheckout() async {
    setState(() => _isLoading = true);
    final result = await ApiService().checkout();
    setState(() => _isLoading = false);

    if (mounted) {
      final bool success = result?['success'] ?? false;
      if (success) {
        setState(() {
          _quantities.clear();
          _cartProducts = [];
          _totalPrice = 0;
        });
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Text(
              AppStrings.of(context, 'order_success'),
              style: const TextStyle(color: Colors.white),
            ),
            content: Text(
              AppStrings.of(context, 'order_success_msg'),
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  AppStrings.of(context, 'ok'),
                  style: const TextStyle(color: Color(0xFF00FF88)),
                ),
              ),
            ],
          ),
        );
      } else {
        final errorMsg =
            result?['message'] ?? AppStrings.of(context, 'checkout_failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService().currentUser;
    final String customerName = user?.name ?? '';
    final String repName = user?.representativeName ?? '';
    final bool hasItems = _quantities.values.any((quantity) => quantity > 0);
    // السماح بإتمام الطلب إذا كان هناك منتجات أو المجموع أكبر من صفر
    final bool canSubmit = (hasItems || _totalPrice > 0);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(AppStrings.of(context, 'cart')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshGoods),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshGoods,
        color: const Color(0xFF00FF88),
        backgroundColor: const Color(0xFF1E1E1E),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                    Text(
                      AppStrings.of(context, 'order_info'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      AppStrings.of(context, 'customer'),
                      customerName,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      AppStrings.of(context, 'representative'),
                      repName,
                    ),
                    if (repName.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.of(context, 'no_rep_found'),
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // قسم المنتجات المضافة فعلياً للسلة
              if (hasItems) ...[
                Row(
                  children: [
                    const Icon(Icons.shopping_basket, color: Color(0xFF00FF88)),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.of(context, 'your_selected_products'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // عرض المنتجات من قائمة السلة خصيصاً
                ..._cartProducts.map((good) {
                  final qty = _quantities[good.id] ?? 0;
                  if (qty <= 0) return const SizedBox.shrink();

                  final displayName =
                      good.nameAr.isNotEmpty ? good.nameAr : good.nameEn;
                  final displayPrice = good.priceAfterDiscount ?? good.price;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00FF88).withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: good.image.isNotEmpty
                              ? Image.network(
                                  _safeUrl(good.image),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.shopping_bag,
                                  color: Colors.grey,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$qty x $displayPrice ${AppStrings.of(context, 'currency_jod')}',
                                style: const TextStyle(
                                  color: Color(0xFF00FF88),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () async {
                            setState(() => _isLoading = true);
                            final response = await ApiService().removeFromCart(
                              good.id,
                            );
                            setState(() => _isLoading = false);
                            if (mounted && response != null) {
                              await _loadCart();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () => _openQuantityDialog(good),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),
              ],

              // شريط البحث
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: AppStrings.of(context, 'search_product_hint'),
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF00FF88),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged("");
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStrings.of(context, 'products'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_totalPages > 1)
                    Text(
                      AppStrings.of(context, 'page_of')
                          .replaceAll('{page}', _currentPage.toString())
                          .replaceAll('{total}', _totalPages.toString()),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoading && _goods.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  ),
                )
              else if (_goods.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      AppStrings.of(context, 'no_products_available'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _goods.length,
                  itemBuilder: (context, index) {
                    final good = _goods[index];
                    final int qty = _quantities[good.id] ?? 0;
                    final displayName =
                        good.nameAr.isNotEmpty ? good.nameAr : good.nameEn;
                    final displayPrice = good.priceAfterDiscount ?? good.price;

                    return InkWell(
                      onTap: () async {
                        final result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                GoodDetailScreen(goodId: good.id),
                          ),
                        );
                        if (result == true) {
                          _loadCart();
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: good.image.isNotEmpty
                                  ? Image.network(
                                      _safeUrl(good.image),
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          width: 60,
                                          height: 60,
                                          color: const Color(0xFF2A2A2A),
                                          child: const Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      width: 60,
                                      height: 60,
                                      color: const Color(0xFF2A2A2A),
                                      child: const Icon(
                                        Icons.shopping_bag,
                                        color: Colors.grey,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      if (good.priceAfterDiscount != null) ...[
                                        Text(
                                          '${good.price} ${AppStrings.of(context, 'currency_jod')}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        '$displayPrice ${AppStrings.of(context, 'currency_jod')}',
                                        style: const TextStyle(
                                          color: Color(0xFF00FF88),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  if (qty > 0)
                                    Text(
                                      '${AppStrings.of(context, 'quantity')}: $qty',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    )
                                  else
                                    Text(
                                      AppStrings.of(context, 'not_added'),
                                      style: const TextStyle(
                                        color: Colors.white38,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: good.stock > 0
                                  ? () => _openQuantityDialog(good)
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: good.stock > 0
                                      ? const Color(0xFF00FF88)
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  good.stock > 0 ? Icons.add : Icons.block,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              if (_hasMore && !_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentPage++;
                        });
                        _loadGoods();
                      },
                      icon: const Icon(Icons.arrow_downward),
                      label: Text(AppStrings.of(context, 'load_more')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E1E),
                        foregroundColor: const Color(0xFF00FF88),
                      ),
                    ),
                  ),
                ),
              if (_isLoading && _goods.isNotEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  ),
                ),
              if (hasItems) ...[
                const Divider(color: Colors.white24, height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStrings.of(context, 'total_amount'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_totalPrice.toStringAsFixed(2)} ${AppStrings.of(context, 'currency_jod')}',
                      style: const TextStyle(
                        color: Color(0xFF00FF88),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit ? _handleCheckout : null,
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
                  child: Text(
                    AppStrings.of(context, 'checkout'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text('$label:', style: const TextStyle(color: Colors.white70)),
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

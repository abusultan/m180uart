import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/bluetooth_service.dart';
import '../../data/models/product_models.dart';
import '../../core/app_strings.dart';
import 'product_list_screen.dart';
import 'login_screen.dart';
import 'scan_screen.dart';
import 'device_detail_screen.dart';
import 'dart:async';
import '../widgets/product_thumbnail_widget.dart';

class DashboardScreen extends StatefulWidget {
  final List<Category>? initialSubCategories;
  final String? title;
  final int? currentCategoryId; // Field to track which category we are viewing
  final String currentEntityType;

  const DashboardScreen({
    super.key,
    this.initialSubCategories,
    this.title,
    this.currentCategoryId,
    this.currentEntityType = 'category',
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Category>> _categoriesFuture;
  final List<Category> _pagedSubcategories = [];
  final ScrollController _subcategoriesScrollController = ScrollController();
  bool _isLoadingPagedSubcategories = false;
  bool _hasMorePagedSubcategories = true;
  int _pagedSubcategoriesPage = 1;
  String _searchQuery = '';
  List<Product> _productSearchResults = [];
  bool _isSearchingProducts = false;
  bool _isOpeningProduct = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _suggestionDebounce;
  int _suggestionRequestId = 0;
  List<String> _searchSuggestions = [];
  StreamSubscription<String?>? _serialSub;

  static const Map<String, String> _commonTypos = {
    'utlra': 'ultra',
    'iphnoe': 'iphone',
    'samsnug': 'samsung',
    'aplpe': 'apple',
    'galxy': 'galaxy',
  };

  bool get _isPagedHierarchyLevel => widget.initialSubCategories == null;

  int _responsiveGridCrossAxisCount(double width) {
    if (width >= 1300) return 5;
    if (width >= 980) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  double _responsiveGridChildAspectRatio(double width) {
    if (width >= 1300) return 1.08;
    if (width >= 980) return 1.0;
    if (width >= 700) return 0.92;
    return 1.0;
  }

  Future<void> _openProduct(Product product) async {
    if (product.entityType == 'model') {
      if (!mounted) return;
      final modelCategory = Category(
        id: product.id,
        nameAr: product.nameAr,
        nameEn: product.nameEn,
        image: product.image,
        imageUrl: product.image,
        entityType: 'model',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductListScreen(category: modelCategory),
        ),
      );
      return;
    }

    if (_isOpeningProduct) return;
    _isOpeningProduct = true;
    try {
      final typeMachineName =
          await CutterBluetoothService().getTypeMachineNameForItems();
      final items = await ApiService().getProductItems(
        product.id,
        typeMachineName: typeMachineName,
      );
      if (!mounted) return;

      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items found for this product')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(productItem: items.first),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open product')));
    } finally {
      _isOpeningProduct = false;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isPagedHierarchyLevel) {
      _categoriesFuture = Future.value(const <Category>[]);
      _subcategoriesScrollController.addListener(_onSubcategoriesScroll);
      _resetPagedSubcategoriesAndLoad();
      _serialSub = CutterBluetoothService().serialStream.listen((serial) {
        if (!mounted) return;
        if (serial == null || serial.isEmpty) return;
        _resetPagedSubcategoriesAndLoad();
      });
    } else if (widget.initialSubCategories != null) {
      _categoriesFuture = Future.value(widget.initialSubCategories);
    } else {
      _categoriesFuture = _loadCurrentCategories();
      _serialSub = CutterBluetoothService().serialStream.listen((serial) {
        if (!mounted) return;
        if (serial == null || serial.isEmpty) return;
        setState(() {
          _categoriesFuture = _loadCurrentCategories();
        });
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestionDebounce?.cancel();
    _searchController.dispose();
    _serialSub?.cancel();
    _subcategoriesScrollController.dispose();
    super.dispose();
  }

  void _onSubcategoriesScroll() {
    if (!_subcategoriesScrollController.hasClients ||
        _isLoadingPagedSubcategories ||
        !_hasMorePagedSubcategories) {
      return;
    }
    if (_subcategoriesScrollController.position.pixels >=
        _subcategoriesScrollController.position.maxScrollExtent - 220) {
      _loadMorePagedSubcategories();
    }
  }

  Future<void> _resetPagedSubcategoriesAndLoad() async {
    _pagedSubcategories.clear();
    _hasMorePagedSubcategories = true;
    _pagedSubcategoriesPage = 1;
    if (mounted) setState(() {});
    await _loadMorePagedSubcategories();
  }

  Future<void> _loadMorePagedSubcategories() async {
    if (_isLoadingPagedSubcategories || !_hasMorePagedSubcategories) {
      return;
    }
    _isLoadingPagedSubcategories = true;
    if (mounted) setState(() {});

    try {
      final typeMachineName =
          await CutterBluetoothService().getTypeMachineNameForItems();
      late final List<Category> pageItems;
      if (widget.currentCategoryId == null) {
        pageItems = await ApiService().getCategoriesPage(
          page: _pagedSubcategoriesPage,
          typeMachineName: typeMachineName,
        );
      } else {
        pageItems = await ApiService().getCategorySubcategoriesPage(
          widget.currentCategoryId!,
          page: _pagedSubcategoriesPage,
          typeMachineName: typeMachineName,
          currentEntityType: widget.currentEntityType,
        );
      }

      _pagedSubcategories.addAll(pageItems);
      if (pageItems.length < 20) {
        _hasMorePagedSubcategories = false;
      } else {
        _pagedSubcategoriesPage++;
      }
    } catch (_) {
      _hasMorePagedSubcategories = false;
    } finally {
      _isLoadingPagedSubcategories = false;
      if (mounted) setState(() {});
    }
  }

  Future<List<Category>> _loadCurrentCategories() async {
    final typeMachineName =
        await CutterBluetoothService().getTypeMachineNameForItems();

    if (widget.currentCategoryId != null) {
      final subcategories = await ApiService().getCategorySubcategories(
        widget.currentCategoryId!,
        typeMachineName: typeMachineName,
        currentEntityType: widget.currentEntityType,
      );
      return subcategories;
    }

    return ApiService().getCategories(typeMachineName: typeMachineName);
  }

  String _categoryDisplayName(Category cat) {
    return cat.nameEn.isNotEmpty ? cat.nameEn : cat.nameAr;
  }

  String _normalizeQuery(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _applyTypoCorrections(String query) {
    final words = query.split(' ');
    final corrected =
        words.map((w) => _commonTypos[w.toLowerCase()] ?? w).join(' ');
    return corrected;
  }

  void _applySuggestion(String suggestion) {
    final normalized = _normalizeQuery(suggestion);
    _searchController.value = TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
    _onSearchChanged(normalized);
  }

  void _updateSuggestions(String query) {
    _suggestionDebounce?.cancel();
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty) {
      if (mounted) {
        setState(() {
          _searchSuggestions = [];
        });
      }
      return;
    }

    final corrected = _applyTypoCorrections(normalized);
    final local = <String>[
      if (corrected.toLowerCase() != normalized.toLowerCase()) corrected,
    ];

    for (final cat in _pagedSubcategories) {
      final name = _categoryDisplayName(cat);
      if (name.toLowerCase().contains(normalized.toLowerCase())) {
        local.add(name);
      }
      if (local.length >= 6) break;
    }

    setState(() {
      _searchSuggestions = local.toSet().take(6).toList();
    });

    _suggestionDebounce = Timer(const Duration(milliseconds: 250), () async {
      final reqId = ++_suggestionRequestId;
      try {
        final typeMachineName =
            await CutterBluetoothService().getTypeMachineNameForItems();
        final products = await ApiService().searchAllProducts(
          normalized,
          typeMachineName: typeMachineName,
        );
        if (!mounted || reqId != _suggestionRequestId) return;

        final merged = <String>[..._searchSuggestions];
        for (final p in products) {
          final name = p.nameEn.isNotEmpty ? p.nameEn : p.nameAr;
          if (name.isEmpty) continue;
          if (!merged.contains(name)) {
            merged.add(name);
          }
          if (merged.length >= 8) break;
        }

        setState(() {
          _searchSuggestions = merged;
        });
      } catch (_) {
        // Keep local suggestions only.
      }
    });
  }

  void _onSearchChanged(String query) {
    final normalized = _normalizeQuery(query);
    setState(() {
      _searchQuery = normalized;
    });
    _updateSuggestions(normalized);

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (normalized.isEmpty) {
      setState(() {
        _productSearchResults = [];
        _isSearchingProducts = false;
        _searchSuggestions = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      setState(() {
        _isSearchingProducts = true;
      });

      try {
        final typeMachineName =
            await CutterBluetoothService().getTypeMachineNameForItems();
        final products = await ApiService().searchAllProducts(
          normalized,
          typeMachineName: typeMachineName,
        );
        if (mounted) {
          setState(() {
            _productSearchResults = products;
            _isSearchingProducts = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isSearchingProducts = false;
            // Optionally handle error
          });
        }
      }
    });
  }

  Timer? _longPressTimer;
  void _startBypassTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(seconds: 5), () {
      HapticFeedback.heavyImpact(); // Give feedback to user
      _showBypassDialog();
    });
  }

  void _cancelBypassTimer() {
    _longPressTimer?.cancel();
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(dialogContext, 'logout_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          AppStrings.of(dialogContext, 'logout_confirm'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppStrings.of(dialogContext, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ApiService().logout();
              await CutterBluetoothService().disconnect();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: Text(
              AppStrings.of(context, 'logout'),
              style: const TextStyle(
                color: Color(0xFF00FF88),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _requestRepresentative() {
    final user = ApiService().currentUser;
    final repName =
        (user?.distributorName != null && user!.distributorName!.isNotEmpty)
            ? user.distributorName!
            : (user?.representativeName ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          AppStrings.of(context, 'request_rep'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          repName.isEmpty
              ? AppStrings.of(context, 'no_rep_found')
              : '${AppStrings.of(context, 'rep_notification_msg')}$repName',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              AppStrings.of(context, 'cancel'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          if (repName.isNotEmpty)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                final result = await ApiService().requestDistributor();
                if (!mounted) return;

                final bool success = result['success'] ?? false;
                String message = result['message']?.toString() ?? '';

                if (message == 'There is no distributor for this user.') {
                  message = AppStrings.of(context, 'no_rep_found');
                } else if (message ==
                    'You have an active distributor request.') {
                  message = AppStrings.of(
                    context,
                    'active_distributor_request',
                  );
                } else if (message == 'distributor created successfully') {
                  message = AppStrings.of(
                    context,
                    'distributor_request_success',
                  );
                }

                if (message.isEmpty) {
                  message = success
                      ? AppStrings.of(context, 'distributor_request_success')
                      : AppStrings.of(context, 'error_generic');
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor:
                        success ? const Color(0xFF00FF88) : Colors.redAccent,
                  ),
                );
              },
              child: Text(
                AppStrings.of(context, 'send'),
                style: const TextStyle(color: Color(0xFF00FF88)),
              ),
            ),
        ],
      ),
    );
  }

  void _showBypassDialog() {
    final passController = TextEditingController();
    String selectedSimType = "SJC";
    final currentAgent = CutterBluetoothService().cachedAgentType;

    // Pre-select based on current bypass setting
    if (currentAgent == "ROCKSPACE_BLUE") {
      selectedSimType = "ROCKSPACE";
    } else if (currentAgent == "DQ") {
      selectedSimType = "DQ";
    } else if (currentAgent == "OLD_V1") {
      selectedSimType = "V1";
    }

    bool showTypeSelection = CutterBluetoothService().isBypassMode;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setAltState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(
            showTypeSelection
                ? AppStrings.of(context, 'choose_machine_type')
                : AppStrings.of(context, 'enter_password'),
            style: const TextStyle(color: Colors.white),
          ),
          content: !showTypeSelection
              ? TextField(
                  controller: passController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: AppStrings.of(context, 'password'),
                    hintStyle: const TextStyle(color: Colors.grey),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.of(context, 'select_machine_to_simulate'),
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedSimType,
                      dropdownColor: const Color(0xFF1E1E1E),
                      style: const TextStyle(color: Colors.white),
                      items: [
                        DropdownMenuItem(
                          value: "SJC",
                          child: Text(AppStrings.of(context, 'sim_type_sjc')),
                        ),
                        DropdownMenuItem(
                          value: "ROCKSPACE",
                          child: Text(
                            AppStrings.of(context, 'sim_type_rockspace'),
                          ),
                        ),
                        DropdownMenuItem(
                          value: "DQ",
                          child: Text(AppStrings.of(context, 'sim_type_dq')),
                        ),
                        DropdownMenuItem(
                          value: "V1",
                          child:
                              Text(AppStrings.of(context, 'sim_type_old_v1')),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setAltState(() => selectedSimType = val);
                        }
                      },
                    ),
                  ],
                ),
          actions: [
            if (CutterBluetoothService().isBypassMode)
              TextButton(
                onPressed: () {
                  CutterBluetoothService().setBypassMode(false);
                  Navigator.pop(context);
                  setState(() {
                    _categoriesFuture = _loadCurrentCategories();
                  });
                },
                child: Text(
                  AppStrings.of(context, 'exit_bypass'),
                  style: TextStyle(color: Colors.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppStrings.of(context, 'cancel')),
            ),
            TextButton(
              onPressed: () {
                if (!showTypeSelection) {
                  if (passController.text == "4336") {
                    setAltState(() => showTypeSelection = true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppStrings.of(context, 'wrong_password')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  // Apply Bypass
                  String agent = "HandshakeNew";
                  String serial = "SUNSHINE_BYPASS";

                  if (selectedSimType == "ROCKSPACE") {
                    agent = "ROCKSPACE_BLUE";
                    serial = "ROCK_BYPASS";
                  } else if (selectedSimType == "DQ") {
                    agent = "DQ";
                    serial = "DQ_BYPASS";
                  } else if (selectedSimType == "V1") {
                    agent = "OLD_V1";
                    serial = "OLD_BYPASS";
                  }

                  CutterBluetoothService().setBypassMode(
                    true,
                    agentType: agent,
                    simulatedSerial: serial,
                  );
                  Navigator.pop(context);
                  setState(() {
                    _categoriesFuture = _loadCurrentCategories();
                  });
                }
              },
              child: Text(
                showTypeSelection
                    ? AppStrings.of(context, 'apply')
                    : AppStrings.of(context, 'ok'),
                style: const TextStyle(color: Color(0xFF00FF88)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCategoryTap(Category cat) {
    final opensNextLevel = cat.children.isNotEmpty ||
        cat.entityType == 'category' ||
        cat.entityType == 'brand';

    if (opensNextLevel) {
      // Navigate to DashboardScreen again but with subcategories
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardScreen(
            title: _categoryDisplayName(cat),
            initialSubCategories: cat.children.isNotEmpty ? cat.children : null,
            currentCategoryId: cat.id,
            currentEntityType: cat.entityType,
          ),
        ),
      );
    } else {
      // Navigate to Product List
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductListScreen(category: cat),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serialNumber = CutterBluetoothService().serialNumber;
    final isConnected = CutterBluetoothService().isConnected;
    final isBypassed = CutterBluetoothService().isBypassMode;
    final canAccess = isConnected || isBypassed;
    final remainingPieces = ApiService().currentUser?.remainingPieces ?? 0;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? AppStrings.of(context, 'categories'),
                    style: const TextStyle(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${AppStrings.of(context, 'remaining')}: $remainingPieces",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00FF88),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            if (isConnected)
              SizedBox(
                height: 18,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    serialNumber ?? AppStrings.of(context, 'system_unknown'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF00FF88),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            else if (isBypassed)
              Text(
                AppStrings.of(context, 'bypass_mode'),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.amber),
            tooltip: AppStrings.of(context, 'request_rep'),
            onPressed: _requestRepresentative,
          ),
          Listener(
            onPointerDown: (_) => _startBypassTimer(),
            onPointerUp: (_) => _cancelBypassTimer(),
            onPointerCancel: (_) => _cancelBypassTimer(),
            child: IconButton(
              icon: Icon(
                Icons.bluetooth,
                color: isConnected
                    ? const Color(0xFF00FF88)
                    : (isBypassed ? Colors.orangeAccent : Colors.grey),
              ),
              onPressed: () async {
                if (isBypassed && !isConnected) {
                  // Quick Switch Mode
                  _showBypassDialog();
                } else {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ScanScreen()),
                  );
                  setState(() {}); // Refresh to show connection status
                }
              },
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: !canAccess
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      size: 80,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppStrings.of(context, 'connect_required_title'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.of(context, 'connect_required_msg'),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScanScreen(),
                          ),
                        );
                        if (!mounted) return;
                        setState(() {
                          _categoriesFuture = _loadCurrentCategories();
                        });
                      },
                      icon: const Icon(Icons.bluetooth),
                      label: Text(AppStrings.of(context, 'go_to_connect')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF88),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: AppStrings.of(context, 'search_hint'),
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                    onSubmitted: (value) {
                      final v = _normalizeQuery(value);
                      if (v.isNotEmpty) {
                        _applySuggestion(v);
                      }
                    },
                  ),
                ),
                if (_searchQuery.isNotEmpty && _searchSuggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _searchSuggestions.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Colors.white10),
                        itemBuilder: (context, index) {
                          final suggestion = _searchSuggestions[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.search,
                              size: 18,
                              color: Colors.grey,
                            ),
                            title: Text(
                              suggestion,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _applySuggestion(suggestion),
                          );
                        },
                      ),
                    ),
                  ),
                Expanded(
                  child: _searchQuery.isNotEmpty
                      ? _buildSearchResults(context)
                      : _isPagedHierarchyLevel
                          ? RefreshIndicator(
                              color: const Color(0xFF00FF88),
                              onRefresh: _resetPagedSubcategoriesAndLoad,
                              child: GridView.builder(
                                controller: _subcategoriesScrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                physics: const AlwaysScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _responsiveGridCrossAxisCount(
                                    MediaQuery.of(context).size.width,
                                  ),
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio:
                                      _responsiveGridChildAspectRatio(
                                    MediaQuery.of(context).size.width,
                                  ),
                                ),
                                itemCount: _pagedSubcategories.length +
                                    ((_hasMorePagedSubcategories ||
                                            _isLoadingPagedSubcategories)
                                        ? 1
                                        : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _pagedSubcategories.length) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF00FF88),
                                      ),
                                    );
                                  }
                                  return _buildCategoryCard(
                                    _pagedSubcategories[index],
                                  );
                                },
                              ),
                            )
                          : RefreshIndicator(
                              color: const Color(0xFF00FF88),
                              onRefresh: () async {
                                // Update User Info
                                await ApiService().getUserInfo().then((_) {
                                  if (mounted) setState(() {});
                                });

                                setState(() {
                                  _searchQuery = ''; // Clear search on refresh
                                  _categoriesFuture = _loadCurrentCategories();
                                });
                                await _categoriesFuture;
                              },
                              child: FutureBuilder<List<Category>>(
                                future: _categoriesFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF00FF88),
                                      ),
                                    );
                                  }

                                  if (snapshot.hasError) {
                                    return Center(
                                      child: SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: Text(
                                          "Error: ${snapshot.error}",
                                          style: const TextStyle(
                                              color: Colors.red),
                                        ),
                                      ),
                                    );
                                  }

                                  if (!snapshot.hasData ||
                                      snapshot.data!.isEmpty) {
                                    return Center(
                                      child: SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          child: Text(
                                            AppStrings.of(
                                                context, 'no_categories'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  // Filter categories based on _searchQuery if it's not empty
                                  final filteredCategories = snapshot.data!
                                      .where(
                                        (cat) => _categoryDisplayName(
                                          cat,
                                        ).toLowerCase().contains(
                                              _searchQuery.toLowerCase(),
                                            ),
                                      )
                                      .toList();

                                  if (filteredCategories.isEmpty &&
                                      _searchQuery.isNotEmpty) {
                                    return Center(
                                      child: SingleChildScrollView(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        child: Container(
                                          padding: const EdgeInsets.all(20),
                                          child: Text(
                                            AppStrings.of(
                                              context,
                                              'no_matching_categories',
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  return GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount:
                                          _responsiveGridCrossAxisCount(
                                        MediaQuery.of(context).size.width,
                                      ),
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio:
                                          _responsiveGridChildAspectRatio(
                                        MediaQuery.of(context).size.width,
                                      ),
                                    ),
                                    itemCount: filteredCategories.length,
                                    itemBuilder: (context, index) {
                                      final cat = filteredCategories[index];
                                      return _buildCategoryCard(cat);
                                    },
                                  );
                                },
                              ),
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryCard(Category cat) {
    final imageUrl = ApiService().normalizeUrl(
      cat.imageUrl.isNotEmpty ? cat.imageUrl : cat.image,
    );

    return GestureDetector(
      onTap: () => _handleCategoryTap(cat),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 170;
          final iconBoxSize = compact ? 60.0 : 76.0;
          final iconSize = compact ? 22.0 : 26.0;
          final titleFontSize = compact ? 13.0 : 14.0;
          final spacing = compact ? 8.0 : 12.0;
          final cardPadding = compact ? 10.0 : 14.0;

          return Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF252525), Color(0xFF1A1A1A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (imageUrl.isNotEmpty)
                  Container(
                    height: iconBoxSize,
                    width: iconBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(compact ? 14 : 16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            cat.children.isNotEmpty
                                ? Icons.folder_open
                                : Icons.smartphone,
                            size: iconSize,
                            color: Colors.grey,
                          );
                        },
                      ),
                    ),
                  )
                else
                  Container(
                    height: iconBoxSize,
                    width: iconBoxSize,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(compact ? 14 : 16),
                    ),
                    child: Icon(
                      cat.children.isNotEmpty
                          ? Icons.folder_open
                          : Icons.smartphone,
                      size: iconSize,
                      color: const Color(0xFF00FF88),
                    ),
                  ),
                SizedBox(height: spacing),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
                  child: Text(
                    _categoryDisplayName(cat),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    if (_isPagedHierarchyLevel) {
      final matchingCategories = _pagedSubcategories
          .where(
            (cat) => _categoryDisplayName(
              cat,
            ).toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();

      return CustomScrollView(
        slivers: [
          if (matchingCategories.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  AppStrings.of(context, 'matching_categories'),
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _responsiveGridCrossAxisCount(
                    MediaQuery.of(context).size.width,
                  ),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: _responsiveGridChildAspectRatio(
                    MediaQuery.of(context).size.width,
                  ),
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _buildCategoryCard(matchingCategories[index]);
                }, childCount: matchingCategories.length),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                AppStrings.of(context, 'matching_products'),
                style: const TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (_isSearchingProducts)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                ),
              ),
            )
          else if (_productSearchResults.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  AppStrings.of(context, 'no_products_found'),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final product = _productSearchResults[index];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Card(
                    color: const Color(0xFF1E1E1E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ProductThumbnail(
                          productId: product.id,
                          primaryImageUrl: product.image,
                          fit: BoxFit.contain,
                          fallbackIcon: Icons.smartphone,
                        ),
                      ),
                      title: Text(
                        product.nameEn.isNotEmpty
                            ? product.nameEn
                            : product.nameAr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        AppStrings.of(context, 'product_label'),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      onTap: () => _openProduct(product),
                    ),
                  ),
                );
              }, childCount: _productSearchResults.length),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    }

    return FutureBuilder<List<Category>>(
      future: _categoriesFuture,
      builder: (context, snapshot) {
        final List<Category> matchingCategories = [];
        if (snapshot.hasData) {
          matchingCategories.addAll(
            snapshot.data!.where(
              (cat) => _categoryDisplayName(
                cat,
              ).toLowerCase().contains(_searchQuery.toLowerCase()),
            ),
          );
        }

        return CustomScrollView(
          slivers: [
            if (matchingCategories.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    AppStrings.of(context, 'matching_categories'),
                    style: const TextStyle(
                      color: Color(0xFF00FF88),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _responsiveGridCrossAxisCount(
                      MediaQuery.of(context).size.width,
                    ),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: _responsiveGridChildAspectRatio(
                      MediaQuery.of(context).size.width,
                    ),
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildCategoryCard(matchingCategories[index]);
                  }, childCount: matchingCategories.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  AppStrings.of(context, 'matching_products'),
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (_isSearchingProducts)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00FF88)),
                  ),
                ),
              )
            else if (_productSearchResults.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    AppStrings.of(context, 'no_products_found'),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final product = _productSearchResults[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Card(
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ProductThumbnail(
                            productId: product.id,
                            primaryImageUrl: product.image,
                            fit: BoxFit.contain,
                            fallbackIcon: Icons.smartphone,
                          ),
                        ),
                        title: Text(
                          product.nameEn.isNotEmpty
                              ? product.nameEn
                              : product.nameAr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          AppStrings.of(context, 'product_label'),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          _openProduct(product);
                        },
                      ),
                    ),
                  );
                }, childCount: _productSearchResults.length),
              ),
            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

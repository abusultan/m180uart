import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/auth_response.dart';
import '../data/models/product_models.dart';
import '../data/models/representative_model.dart';

class ApiService {
  static ApiService? _instance;
  static bool _initialized = false;
  static Uint8List? _pinnedCert;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final data = await rootBundle.load('assets/certs/cutter_ca.pem');
      _pinnedCert = data.buffer.asUint8List();
    } catch (_) {
      _pinnedCert = null;
    }
    _instance?._configureHttpClientAdapter();
  }

  factory ApiService() {
    return _instance ??= ApiService._internal();
  }

  ApiService._internal() {
    _initDio();
  }

  void _initDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://cutter.irbidbasket.com/api/',
        // baseUrl: 'http://192.168.1.89:8000/api/',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );

    _configureHttpClientAdapter();

    // Add interceptor to inject token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null && _token!.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (e, handler) {
          final status = e.response?.statusCode;
          final method = e.requestOptions.method;
          final uri = e.requestOptions.uri;
          final type = e.type;
          final data = e.response?.data;
          print(
            "API Error: type=$type status=$status method=$method uri=$uri message=${e.message} error=${e.error} data=$data",
          );
          return handler.next(e);
        },
      ),
    );
  }

  late Dio _dio;
  String? _token;
  User? _currentUser;

  void _configureHttpClientAdapter() {
    const allowBadCerts =
        bool.fromEnvironment('ALLOW_BAD_CERTS', defaultValue: false);
    final adapter = _dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        if (_pinnedCert != null) {
          final context = SecurityContext(withTrustedRoots: false);
          context.setTrustedCertificatesBytes(_pinnedCert!);
          return HttpClient(context: context);
        }
        if (kDebugMode && allowBadCerts) {
          final client = HttpClient();
          client.badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
          return client;
        }
        return HttpClient();
      };
    }
  }

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _token != null;

  void setToken(String token) {
    _token = token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    return _token;
  }

  Future<void> clearToken() async {
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // --- Auth ---

  Future<LoginResponse> login(String login, String password) async {
    try {
      final response = await _dio.post(
        'login',
        data: {'login': login, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final loginResponse = LoginResponse.fromJson(response.data);
      if (loginResponse.success && loginResponse.token.isNotEmpty) {
        await saveToken(loginResponse.token);
        _currentUser = loginResponse.user;
      }
      return loginResponse;
    } catch (e) {
      throw Exception("Login failed: $e");
    }
  }

  Future<LoginResponse> register(
    String name,
    String email,
    String phone,
    String address,
    String password,
    String passwordConfirmation, {
    String? machineType,
    String? machineSerial,
    String? machineOwnership,
    int? representativeId,
  }) async {
    try {
      final Map<String, dynamic> payload = {
        'name': name,
        'email': email,
        'phone': phone,
        'address': address,
        'password': password,
        'password_confirmation': passwordConfirmation,
      };

      if (machineType != null && machineType.isNotEmpty) {
        payload['machine_type'] = machineType;
      }
      if (machineSerial != null && machineSerial.isNotEmpty) {
        payload['machine_serial'] = machineSerial;
      }
      if (machineOwnership != null && machineOwnership.isNotEmpty) {
        payload['machine_ownership'] = machineOwnership;
      }
      if (representativeId != null) {
        payload['representative_id'] = representativeId;
      }

      final response = await _dio.post(
        'register',
        data: FormData.fromMap(payload),
      );

      final loginResponse = LoginResponse.fromJson(response.data);
      if (loginResponse.success && loginResponse.token.isNotEmpty) {
        await saveToken(loginResponse.token);
        _currentUser = loginResponse.user;
      }
      return loginResponse;
    } catch (e) {
      // Improve error handling for registration
      if (e is DioException && e.response != null) {
        // You might want to parse validation errors here
        throw Exception(
          "Registration failed: ${e.response?.data['message'] ?? e.message}",
        );
      }
      throw Exception("Registration failed: $e");
    }
  }

  // --- Products ---

  Future<List<Representative>> getRepresentatives() async {
    const endpoints = ['representatives', 'mandobs', 'reps'];
    for (final endpoint in endpoints) {
      try {
        final response = await _dio.get(endpoint);

        dynamic rawData = response.data;
        if (rawData is Map && rawData['success'] == true) {
          rawData = rawData['data'];
        } else if (rawData is Map && rawData.containsKey('data')) {
          rawData = rawData['data'];
        }

        final List list;
        if (rawData is Map && rawData.containsKey('data')) {
          list = rawData['data'];
        } else if (rawData is List) {
          list = rawData;
        } else {
          list = [];
        }

        if (list.isNotEmpty) {
          return list.map((e) => Representative.fromJson(e)).toList();
        }
      } catch (_) {
        // Try next endpoint
      }
    }
    return [];
  }

  Future<List<Category>> getCategories() async {
    try {
      final response = await _dio.get('categories');
      print("Categories Response: ${response.data}");
      if (response.data['success'] == true) {
        if (response.data['data'] == null) {
          print("API Data is null");
          return [];
        }
        // Handle cases where data might be directly the list or nested in 'data' key
        final rawData = response.data['data'];
        final List list = (rawData is Map && rawData.containsKey('data'))
            ? rawData['data']
            : (rawData is List ? rawData : []);

        print("Parsed List Length: ${list.length}");
        return list.map((e) => Category.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get Categories Error: $e');
      return [];
    }
  }

  Future<List<Product>> getCategoryProducts(
    int categoryId,
    int page, {
    String? query,
  }) async {
    try {
      final Map<String, dynamic> params = {'page': page};
      if (query != null && query.isNotEmpty) {
        params['search'] = query;
      }

      print("Getting products for cat: $categoryId, page: $page");
      final response = await _dio.get(
        'categories/$categoryId/products',
        queryParameters: params,
      );

      print("Get Products Response: ${response.data}");
      if (response.data['success'] == true) {
        final rawData = response.data['data'];

        // Handle both paginated (data.data) and non-paginated (data) responses
        final List list;
        if (rawData is Map && rawData.containsKey('data')) {
          list = rawData['data']; // Paginated
        } else if (rawData is List) {
          list = rawData; // Direct list
        } else {
          list = [];
        }

        print("Parsed Products Length: ${list.length}");
        return list.map((e) => Product.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get Products Error: $e');
      return [];
    }
  }

  Future<List<Product>> searchProducts(
    String query, {
    int page = 1,
    int? categoryId,
  }) async {
    try {
      final Map<String, dynamic> params = {'search': query, 'page': page};
      if (categoryId != null) {
        params['category_id'] = categoryId;
      }

      final response = await _dio.get('products', queryParameters: params);

      print("Search Products Response: ${response.data}");
      if (response.data['success'] == true) {
        final rawData = response.data['data'];

        final List list;
        if (rawData is Map && rawData.containsKey('data')) {
          list = rawData['data'];
        } else if (rawData is List) {
          list = rawData;
        } else {
          list = [];
        }

        return list.map((e) => Product.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Search Products Error: $e');
      return [];
    }
  }

  Future<List<Product>> searchAllProducts(String query, {int page = 1}) async {
    try {
      final Map<String, dynamic> params = {'search': query, 'page': page};

      final response = await _dio.get(
        'search-all-products',
        queryParameters: params,
      );

      print("Search All Products Response: ${response.data}");
      if (response.data['success'] == true) {
        final rawData = response.data['data'];

        final List list;
        if (rawData is Map && rawData.containsKey('data')) {
          list = rawData['data'];
        } else if (rawData is List) {
          list = rawData;
        } else {
          list = [];
        }

        return list.map((e) => Product.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Search All Products Error: $e');
      return [];
    }
  }

  Future<List<ProductItem>> getProductItems(int productId) async {
    try {
      final response = await _dio.get('products/$productId/items');
      if (response.data['success'] == true) {
        final List list = response.data['data'];
        return list.map((e) => ProductItem.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Get Items Error: $e');
      return [];
    }
  }

  Future<GoodsPaginationResponse?> getGoods({int page = 1}) async {
    try {
      final response = await _dio.get('goods', queryParameters: {'page': page});

      print("Get Goods Response: ${response.data}");
      if (response.data['status'] == true) {
        return GoodsPaginationResponse.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Get Goods Error: $e');
      return null;
    }
  }

  Future<Good?> getGoodById(int id) async {
    try {
      final response = await _dio.get('goods/$id');

      print("Get Good By ID Response: ${response.data}");
      if (response.data['status'] == true) {
        return Good.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('Get Good By ID Error: $e');
      return null;
    }
  }

  Future<GoodsPaginationResponse?> searchGoods(
    String query, {
    int page = 1,
  }) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await _dio.get(
        'goods/search/$encodedQuery', // استخدام المسار بناءً على كود الباك آند
        queryParameters: {'page': page},
      );

      print("Search Goods Response: ${response.data}");
      if (response.data['status'] == true) {
        return GoodsPaginationResponse.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('Search Goods Error: $e');
      return null;
    }
  }

  // --- Cart System ---

  Future<Map<String, dynamic>?> addToCart(int goodId, int quantity) async {
    try {
      final formData = FormData.fromMap({
        'good_id': goodId.toString(),
        'quantity': quantity.toString(),
      });
      final response = await _dio.post('add-to-cart', data: formData);
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) {
      print('Add to Cart Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCart() async {
    try {
      final response = await _dio.get('get-cart');
      if (response.statusCode == 200 && response.data != null) {
        return response.data;
      }
      return null;
    } catch (e) {
      print('Get Cart Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> removeFromCart(int goodId) async {
    try {
      final formData = FormData.fromMap({'good_id': goodId.toString()});
      final response = await _dio.post('remove-from-cart', data: formData);
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) {
      print('Remove from Cart Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateCartQuantity(
    int goodId,
    int quantity,
  ) async {
    try {
      final formData = FormData.fromMap({
        'good_id': goodId.toString(),
        'quantity': quantity.toString(),
      });
      final response = await _dio.post('update-quantity', data: formData);
      if (response.statusCode == 200) return response.data;
      return null;
    } catch (e) {
      print('Update Quantity Error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkout() async {
    try {
      final response = await _dio.post('checkout');
      return {'success': response.statusCode == 200, 'data': response.data};
    } catch (e) {
      if (e is DioException && e.response != null) {
        return {'success': false, 'message': e.response?.data['message']};
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- User ---

  Future<User?> getUserInfo() async {
    try {
      final response = await _dio.get('user');
      if (response.data['success'] == true) {
        final user = User.fromJson(response.data['data']);
        _currentUser = user; // Update local cache
        return user;
      }
      return null;
    } catch (e) {
      print('Get User Info Error: $e');
      return null;
    }
  }

  Future<bool> addDevice(String serialNumber, String handshake) async {
    try {
      final response = await _dio.post(
        'add-device',
        data: {'serial_number': serialNumber, 'hand_shake': handshake},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final success = response.data['success'] == true;
      print("Add device response: ${response.data}");
      return success;
    } catch (e) {
      print('Add Device Error: $e');
      return false;
    }
  }

  Future<String?> getDeviceBySerialNumber(String serialNumber) async {
    try {
      final response = await _dio.post(
        'get-device-by-serial-number',
        data: {'serial_number': serialNumber},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      print("Get Device Response: ${response.data}");
      if (response.data['success'] == true && response.data['data'] != null) {
        return response.data['data']['hand_shake'];
      }
      return null;
    } catch (e) {
      print('Get Device Error: $e');
      return null;
    }
  }

  Future<bool> recordCutterUse(
    String productItemId,
    String serialNumber,
  ) async {
    try {
      final response = await _dio.post(
        'cutter-use',
        data: {'product_item_id': productItemId, 'serial_number': serialNumber},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final success = response.data['success'] == true;
      if (success) {
        // Update local user remaining pieces if available in response,
        // otherwise just decrement locally.
        // Assuming the API might return the new user object or just success.
        // If not provided, we manually decrement.
        if (_currentUser != null) {
          // It's safer to fetch fresh user info, but for speed we decrement
          int newCount = _currentUser!.remainingPieces - 1;
          if (newCount < 0) newCount = 0;

          _currentUser = User(
            id: _currentUser!.id,
            name: _currentUser!.name,
            email: _currentUser!.email,
            phone: _currentUser!.phone,
            address: _currentUser!.address,
            remainingPieces: newCount,
          );
        }
      } else {
        // Check for specific message
        final message = response.data['message'];
        if (message == "Not enough pieces") {
          throw Exception(message);
        }
      }

      return success;
    } catch (e) {
      print('Record Use Error: $e');
      // Re-throw if it's our specific exception
      if (e.toString().contains("Not enough pieces")) {
        rethrow;
      }
      return false;
    }
  }

  // --- File ---

  Future<File?> downloadFile(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      // Create a sensible filename from URL or timestamp
      final filename = "cut_file_${DateTime.now().millisecondsSinceEpoch}.file";
      final savePath = "${dir.path}/$filename";

      // Full URL check (if relative, append base)
      if (!url.startsWith('http')) {
        // ZjConfig.API_BASE_URL might be part of it, but usually file URLs are separate.
        // If fileUrl comes from API response as full URL, we are good.
        // If it's relative like "uploads/...", append base.
        // Assuming full URL for now based on Java 'downloadFile(@Url String fileUrl)'
      }

      final safeUrl = _safeUrl(url);
      await _dio.download(safeUrl, savePath);
      return File(savePath);
    } catch (e) {
      print('Download Error: $e');
      return null;
    }
  }

  String normalizeUrl(String url) => _safeUrl(url);

  String _safeUrl(String url) {
    if (url.isEmpty) return url;
    var trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;

    final base = _dio.options.baseUrl;
    final fileBase = base.endsWith('/api/')
        ? base.replaceFirst(RegExp(r'/api/?$'), '/')
        : base;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.encodeFull(trimmed);
    }

    trimmed = trimmed.replaceFirst(RegExp(r'^/'), '');
    trimmed = trimmed.replaceFirst(RegExp(r'^cutter/'), '');
    trimmed = trimmed.replaceFirst(RegExp(r'^storage/app/public/'), 'storage/');
    trimmed = trimmed.replaceFirst(RegExp(r'^public/storage/'), 'storage/');

    final full = '$fileBase$trimmed';
    return Uri.encodeFull(full);
  }
}

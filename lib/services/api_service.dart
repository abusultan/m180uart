import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/auth_response.dart';
import '../data/models/product_models.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();

  factory ApiService() {
    return _instance;
  }

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://cutter.irbidbasket.com/api/',
        // baseUrl: 'http://192.168.1.89:8000/api/',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );

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
          print("API Error: ${e.message} path: ${e.requestOptions.path}");
          return handler.next(e);
        },
      ),
    );
  }

  late Dio _dio;
  String? _token;
  User? _currentUser;

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
    String passwordConfirmation,
  ) async {
    try {
      final response = await _dio.post(
        'register',
        data: FormData.fromMap({
          'name': name,
          'email': email,
          'phone': phone,
          'address': address,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
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

  Future<bool> recordCutterUse(String productItemId) async {
    try {
      final response = await _dio.post(
        'cutter-use',
        data: {'product_item_id': productItemId},
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
    final fileBase =
        base.endsWith('/api/') ? base.replaceFirst(RegExp(r'/api/?$'), '/') : base;

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

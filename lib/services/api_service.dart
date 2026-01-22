import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
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
        baseUrl: 'http://192.168.1.89:8000/api/',
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
        _token = loginResponse.token;
        _currentUser = loginResponse.user;
      }
      return loginResponse;
    } catch (e) {
      throw Exception("Login failed: $e");
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

      return response.data['success'] == true;
    } catch (e) {
      print('Record Use Error: $e');
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

      await _dio.download(url, savePath);
      return File(savePath);
    } catch (e) {
      print('Download Error: $e');
      return null;
    }
  }
}

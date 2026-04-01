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
        baseUrl: 'https://anti-crash.com/api/',
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
  bool _isRockspaceMode = false;
  bool get isRockspaceMode => _isRockspaceMode;

  void setRockspaceMode(bool value) {
    _isRockspaceMode = value;
  }

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

  Future<void> logout() async {
    final tokenToKill = _token;
    await clearToken();
    if (tokenToKill == null || tokenToKill.isEmpty) return;
    try {
      await _dio.post(
        'logout',
        options: Options(headers: {'Authorization': 'Bearer $tokenToKill'}),
      );
    } catch (_) {
      // Keep local logout successful even if remote call fails.
    }
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
    int? distributorId,
    String? location,
  }) async {
    try {
      final cleanedName = name.trim();
      final cleanedEmail = email.trim();
      final cleanedPhone = phone.trim();
      final cleanedAddress = address.trim();
      final cleanedPassword = password.trim();
      final cleanedPasswordConfirmation = passwordConfirmation.trim();
      final cleanedLocation = location?.trim() ?? '';
      final cleanedMachineType = machineType?.trim() ?? '';
      final cleanedMachineSerial = machineSerial?.trim() ?? '';
      final normalizedOwnership = _normalizeMachineOwnership(machineOwnership);
      final Map<String, dynamic> payload = {
        'name': cleanedName,
        'email': cleanedEmail,
        'phone': cleanedPhone,
        'address': cleanedAddress,
        'password': cleanedPassword,
        'password_confirmation': cleanedPasswordConfirmation,
      };

      if (cleanedLocation.isNotEmpty) {
        payload['location'] = cleanedLocation;
      }

      if (cleanedMachineType.isNotEmpty) {
        payload['type_machine'] = cleanedMachineType;
      }
      if (cleanedMachineSerial.isNotEmpty) {
        payload['serial_number'] = cleanedMachineSerial;
      }
      if (normalizedOwnership != null) {
        payload['machine_ownership'] = normalizedOwnership;
      }
      if (distributorId != null) {
        payload['distributor_id'] = distributorId;
      }

      final response = await _dio.post(
        'register',
        data: payload,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final loginResponse = LoginResponse.fromJson(response.data);
      if (loginResponse.success && loginResponse.token.isNotEmpty) {
        await saveToken(loginResponse.token);
        _currentUser = loginResponse.user;
      }
      return loginResponse;
    } catch (e) {
      if (e is DioException && e.response != null) {
        throw Exception(_extractApiErrorMessage(e.response?.data, e.message));
      }
      throw Exception("Registration failed: $e");
    }
  }

  Future<Map<String, dynamic>> requestDistributor() async {
    try {
      final response = await _dio.post('distributor/request');
      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};
      return {
        'success': data['success'] == true,
        'message': data['message']?.toString(),
      };
    } catch (e) {
      if (e is DioException && e.response?.data is Map) {
        final body = e.response!.data as Map;
        return {
          'success': false,
          'message': body['message']?.toString() ?? 'Request failed',
        };
      }
      return {'success': false, 'message': e.toString()};
    }
  }

  // --- Products ---

  Future<List<Representative>> getRepresentatives() async {
    const endpoints = ['distributors/all'];
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

  String? _normalizeMachineOwnership(String? rawValue) {
    final value = rawValue?.trim().toLowerCase();
    switch (value) {
      case 'owner':
      case 'true':
      case '1':
        return '1';
      case 'rent':
      case 'false':
      case '0':
        return '0';
      default:
        return null;
    }
  }

  String _extractApiErrorMessage(dynamic body, String? fallbackMessage) {
    if (body is Map) {
      final errors = body['errors'];
      if (errors is Map) {
        for (final value in errors.values) {
          if (value is List && value.isNotEmpty) {
            final first = value.first?.toString().trim() ?? '';
            if (first.isNotEmpty) return first;
          }
          final text = value?.toString().trim() ?? '';
          if (text.isNotEmpty) return text;
        }
      }

      final message = body['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) return message;
    }

    final fallback = fallbackMessage?.trim() ?? '';
    if (fallback.isNotEmpty) return fallback;
    return 'Registration failed';
  }

  List<dynamic> _extractListFromPayload(dynamic payload) {
    if (payload is Map && payload.containsKey('data')) {
      final nested = payload['data'];
      if (nested is List) return nested;
      if (nested is Map && nested.containsKey('data')) {
        final deep = nested['data'];
        if (deep is List) return deep;
      }
    }
    if (payload is List) return payload;
    return const [];
  }

  List<Category> _mapCategoryLikeList(List<dynamic> list, String entityType) {
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) {
          final map = Map<String, dynamic>.from(e);
          map['__entity_type'] = entityType;
          return Category.fromJson(map);
        })
        .toList();
  }

  Future<List<dynamic>> _fetchList(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.get(endpoint, queryParameters: queryParameters);
    if (response.data is! Map<String, dynamic>) {
      return const [];
    }
    final payload = response.data as Map<String, dynamic>;
    if (payload['success'] == false) return const [];
    return _extractListFromPayload(payload['data']);
  }

  Future<List<dynamic>> _fetchAllPagedList(
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    int startPage = 1,
  }) async {
    final results = <dynamic>[];
    var page = startPage;
    const maxPages = 200;

    for (var i = 0; i < maxPages; i++) {
      final params = <String, dynamic>{...?queryParameters, 'page': page};
      final response = await _dio.get(endpoint, queryParameters: params);

      if (response.data is! Map<String, dynamic>) {
        break;
      }
      final payload = response.data as Map<String, dynamic>;
      if (payload['success'] == false || payload['data'] == null) {
        break;
      }

      final pageItems = _extractListFromPayload(payload['data']);
      if (pageItems.isNotEmpty) {
        results.addAll(pageItems);
      }

      final dataRoot = payload['data'];
      final lastPage =
          dataRoot is Map ? int.tryParse('${dataRoot['last_page'] ?? ''}') : null;
      final nextPageUrl = dataRoot is Map ? dataRoot['next_page_url'] : null;

      if (lastPage != null) {
        if (page >= lastPage) break;
        page++;
        continue;
      }

      if (nextPageUrl == null || pageItems.isEmpty) {
        break;
      }
      page++;
    }

    return results;
  }

  Future<List<Category>> getCategories({String? typeMachineName}) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        queryParameters['type_machine_name'] = typeMachineName.trim();
      }

      final list = await _fetchAllPagedList(
        'categories',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

      return _mapCategoryLikeList(list, 'category');
    } catch (e) {
      print('Get Categories Error: $e');
      return [];
    }
  }

  Future<Category?> getCategoryById(
    int categoryId, {
    String? typeMachineName,
  }) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        queryParameters['type_machine_name'] = typeMachineName.trim();
      }

      final response = await _dio.get(
        'categories/$categoryId',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

      if (response.data['success'] == true && response.data['data'] != null) {
        return Category.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      print('Get Category By ID Error: $e');
      return null;
    }
  }

  Future<List<Category>> getCategorySubcategories(
    int categoryId, {
    int page = 1,
    String? typeMachineName,
    String currentEntityType = 'category',
  }) async {
    final queryParameters = <String, dynamic>{'page': page};
    if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
      queryParameters['type_machine_name'] = typeMachineName.trim();
    }

    if (currentEntityType == 'model') {
      return [];
    }

    try {
      if (currentEntityType == 'category') {
        final brands = await _fetchAllPagedList(
          'categories/$categoryId/brands',
          queryParameters: queryParameters,
          startPage: page,
        );
        return _mapCategoryLikeList(brands, 'brand');
      }

      if (currentEntityType == 'brand') {
        final models = await _fetchAllPagedList(
          'brands/$categoryId/models',
          queryParameters: queryParameters,
          startPage: page,
        );
        return _mapCategoryLikeList(models, 'model');
      }
    } catch (_) {
      // Fallback to legacy endpoints below.
    }

    try {
      final legacy = await _fetchList(
        'categories/$categoryId/subcategories',
        queryParameters: queryParameters,
      );
      return _mapCategoryLikeList(legacy, 'category');
    } catch (e) {
      print('Get Category Subcategories Error: $e');
      return [];
    }
  }

  Future<List<Category>> getCategoriesPage({
    int page = 1,
    String? typeMachineName,
  }) async {
    try {
      final queryParameters = <String, dynamic>{'page': page};
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        queryParameters['type_machine_name'] = typeMachineName.trim();
      }

      final list = await _fetchList(
        'categories',
        queryParameters: queryParameters,
      );
      return _mapCategoryLikeList(list, 'category');
    } catch (e) {
      print('Get Categories Page Error: $e');
      return [];
    }
  }

  Future<List<Category>> getCategorySubcategoriesPage(
    int categoryId, {
    int page = 1,
    String? typeMachineName,
    String currentEntityType = 'category',
  }) async {
    final queryParameters = <String, dynamic>{'page': page};
    if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
      queryParameters['type_machine_name'] = typeMachineName.trim();
    }
    if (currentEntityType == 'model') {
      return [];
    }

    try {
      if (currentEntityType == 'category') {
        final brands = await _fetchList(
          'categories/$categoryId/brands',
          queryParameters: queryParameters,
        );
        return _mapCategoryLikeList(brands, 'brand');
      }

      if (currentEntityType == 'brand') {
        final models = await _fetchList(
          'brands/$categoryId/models',
          queryParameters: queryParameters,
        );
        return _mapCategoryLikeList(models, 'model');
      }
    } catch (_) {
      // Fallback to legacy endpoint below.
    }

    try {
      final legacy = await _fetchList(
        'categories/$categoryId/subcategories',
        queryParameters: queryParameters,
      );
      return _mapCategoryLikeList(legacy, 'category');
    } catch (e) {
      print('Get Category Subcategories Page Error: $e');
      return [];
    }
  }

  Future<List<Category>> getAllSubcategories({String? typeMachineName}) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        queryParameters['type_machine_name'] = typeMachineName.trim();
      }

      final legacy = await _fetchList(
        'subcategories',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );
      return _mapCategoryLikeList(legacy, 'category');
    } catch (e) {
      print('Get All Subcategories Error: $e');
      return [];
    }
  }

  Future<List<Product>> getCategoryProducts(
    int categoryId,
    int page, {
    String? query,
    String? typeMachineName,
    String entityType = 'category',
  }) async {
    final Map<String, dynamic> params = {'page': page};
    if (query != null && query.isNotEmpty) {
      params['search'] = query;
    }
    if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
      params['type_machine_name'] = typeMachineName.trim();
    }

    try {
      if (entityType == 'model') {
        final response = await _dio.get(
          'models/$categoryId/products',
          queryParameters: params,
        );
        final list = _extractListFromPayload(response.data['data']);
        return list.map((e) => Product.fromJson(e)).toList();
      }

      final filterKey = entityType == 'brand' ? 'brand_id' : 'category_id';
      final response = await _dio.get(
        'products',
        queryParameters: {...params, filterKey: categoryId},
      );
      final list = _extractListFromPayload(response.data['data']);
      return list.map((e) => Product.fromJson(e)).toList();
    } catch (_) {
      // Fallback to legacy endpoint.
    }

    try {
      final response = await _dio.get(
        'categories/$categoryId/products',
        queryParameters: params,
      );
      final list = _extractListFromPayload(response.data['data']);
      return list.map((e) => Product.fromJson(e)).toList();
    } catch (e) {
      print('Get Products Error: $e');
      return [];
    }
  }

  Future<List<Product>> searchProducts(
    String query, {
    int page = 1,
    int? categoryId,
    String categoryEntityType = 'category',
    String? typeMachineName,
  }) async {
    try {
      final Map<String, dynamic> params = {'search': query, 'page': page};
      if (categoryId != null) {
        if (categoryEntityType == 'brand') {
          params['brand_id'] = categoryId;
        } else if (categoryEntityType == 'model') {
          params['model_id'] = categoryId;
        } else {
          params['category_id'] = categoryId;
        }
      }
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        params['type_machine_name'] = typeMachineName.trim();
      }

      final response = await _dio.get('products', queryParameters: params);

      final list = _extractListFromPayload(response.data['data']);
      return list.map((e) => Product.fromJson(e)).toList();
    } catch (e) {
      print('Search Products Error: $e');
      return [];
    }
  }

  Future<List<Product>> searchAllProducts(
    String query, {
    int page = 1,
    String? typeMachineName,
  }) async {
    try {
      final cleanedQuery = query.trim().replaceAll(RegExp(r'\s+'), ' ');
      final Map<String, dynamic> params = {
        'search': cleanedQuery,
        'q': cleanedQuery,
        'page': page,
      };
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        params['type_machine_name'] = typeMachineName.trim();
      }

      try {
        final response = await _dio.get(
          'search-all-products',
          queryParameters: params,
        );
        var list = _extractListFromPayload(response.data['data']);

        // If full-phrase search returns nothing, fallback to term-based search
        // (useful for minor typos/order issues like "s25 utlra").
        if (list.isEmpty && cleanedQuery.contains(' ')) {
          final words = cleanedQuery
              .split(' ')
              .map((w) => w.trim())
              .where((w) => w.length >= 2)
              .toList();
          final merged = <Map<String, dynamic>>[];
          final seen = <int>{};

          for (final word in words) {
            final wordParams = <String, dynamic>{
              'search': word,
              'q': word,
              'page': page,
            };
            if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
              wordParams['type_machine_name'] = typeMachineName.trim();
            }

            final wordResponse = await _dio.get(
              'search-all-products',
              queryParameters: wordParams,
            );
            final wordList = _extractListFromPayload(wordResponse.data['data']);
            for (final item in wordList) {
              if (item is Map<String, dynamic>) {
                final id = int.tryParse('${item['id'] ?? ''}') ?? 0;
                if (id > 0 && seen.add(id)) {
                  merged.add(item);
                }
              }
            }
          }
          list = merged;
        }

        return list.map((e) => Product.fromJson(e)).toList();
      } catch (_) {
        final response = await _dio.get('products', queryParameters: params);
        final list = _extractListFromPayload(response.data['data']);
        return list.map((e) => Product.fromJson(e)).toList();
      }
    } catch (e) {
      print('Search All Products Error: $e');
      return [];
    }
  }

  Future<List<ProductItem>> getProductItems(
    int productId, {
    String? typeMachineName,
  }) async {
    try {
      final queryParameters = <String, dynamic>{};
      if (typeMachineName != null && typeMachineName.trim().isNotEmpty) {
        queryParameters['type_machine_name'] = typeMachineName.trim();
      }

      try {
        final response = await _dio.get(
          'products/$productId/items',
          queryParameters: queryParameters.isEmpty ? null : queryParameters,
        );
        final list = _extractListFromPayload(response.data['data']);
        if (list.isNotEmpty) {
          return list.map((e) => ProductItem.fromJson(e)).toList();
        }
      } catch (_) {
        // Fallback to new product details endpoint.
      }

      final response = await _dio.get(
        'products/$productId',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );

      if (response.data is Map<String, dynamic> &&
          response.data['success'] == true &&
          response.data['data'] is Map) {
        final item = Map<String, dynamic>.from(response.data['data'] as Map);
        item['product_id'] = productId;
        return [ProductItem.fromJson(item)];
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

  Future<bool> addDevice(
    String serialNumber,
    String handshake, {
    String? machineType,
    String? machineName,
  }) async {
    try {
      final cleanedSerial = serialNumber.trim();
      final cleanedHandshake = handshake.trim();
      final cleanedMachineType = (machineType ?? '').trim();
      final cleanedMachineName = (machineName ?? '').trim();
      final payload = <String, dynamic>{
        'serial_number': cleanedSerial,
        'hand_shake': cleanedHandshake,
        'handshake': cleanedHandshake,
        'handShake': cleanedHandshake,
        'algorithm': cleanedHandshake,
        'agent_type': cleanedHandshake,
      };
      if (cleanedMachineType.isNotEmpty) {
        payload['type_machine'] = cleanedMachineType;
      }

      final resolvedDisplayName = cleanedMachineName.isNotEmpty
          ? cleanedMachineName
          : cleanedMachineType;
      if (resolvedDisplayName.isNotEmpty) {
        payload['name'] = resolvedDisplayName;
        payload['machine_name'] = resolvedDisplayName;
        payload['model'] = resolvedDisplayName;
        payload['device_name'] = resolvedDisplayName;
      }

      final response = await _dio.post(
        'add-device',
        data: payload,
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
        final data = response.data['data'];
        if (data is Map<String, dynamic>) {
          final candidates = [
            data['hand_shake'],
            data['handshake'],
            data['handShake'],
            data['algorithm'],
            data['agent_type'],
            data['agent'],
          ];
          for (final value in candidates) {
            final text = value?.toString().trim() ?? '';
            if (text.isNotEmpty && text.toLowerCase() != 'null') {
              return text;
            }
          }
        }
      }
      return null;
    } catch (e) {
      print('Get Device Error: $e');
      return null;
    }
  }

  Future<int?> getCutterIdBySerialNumber(String serialNumber) async {
    try {
      final response = await _dio.post(
        'get-device-by-serial-number',
        data: {'serial_number': serialNumber},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      if (response.data['success'] == true && response.data['data'] is Map) {
        final map = Map<String, dynamic>.from(response.data['data']);
        final candidates = [map['cutter_id'], map['id'], map['device_id']];
        for (final value in candidates) {
          final parsed = int.tryParse('${value ?? ''}');
          if (parsed != null && parsed > 0) return parsed;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> decrementRemainingPieces({
    required int productId,
    int? cutterId,
  }) async {
    try {
      final payload = <String, dynamic>{'product_id': productId};
      if (cutterId != null) payload['cutter_id'] = cutterId;
      final response = await _dio.post(
        'decrement-pieces',
        data: payload,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};
      final success = data['success'] == true;

      final nextRemaining = data['data'] is Map
          ? int.tryParse('${data['data']['remaining_pieces'] ?? ''}')
          : null;
      if (success && _currentUser != null && nextRemaining != null) {
        _currentUser = User(
          id: _currentUser!.id,
          name: _currentUser!.name,
          email: _currentUser!.email,
          phone: _currentUser!.phone,
          address: _currentUser!.address,
          remainingPieces: nextRemaining,
          representativeName: _currentUser!.representativeName,
          distributorName: _currentUser!.distributorName,
          representativeId: _currentUser!.representativeId,
        );
      }

      return {
        'success': success,
        'message': data['message']?.toString(),
        'remaining_pieces': nextRemaining,
      };
    } catch (e) {
      if (e is DioException && e.response?.data is Map) {
        final body = e.response!.data as Map;
        return {
          'success': false,
          'message': body['message']?.toString() ?? 'Decrement failed',
          'remaining_pieces': null,
        };
      }
      return {
        'success': false,
        'message': e.toString(),
        'remaining_pieces': null,
      };
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

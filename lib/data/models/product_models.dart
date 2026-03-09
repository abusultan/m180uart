String _stripChineseText(String value) {
  if (value.isEmpty) return value;
  final withoutHan = value.replaceAll(
    RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF]'),
    '',
  );
  return withoutHan.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

String _sanitizeName(dynamic value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return '';
  return _stripChineseText(raw);
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

class Category {
  final int id;
  final String nameAr;
  final String nameEn;
  final String image;
  final String imageUrl;
  final String entityType;

  final List<Category> children;

  String get name {
    if (nameEn.isNotEmpty && nameAr.isNotEmpty) {
      return "$nameEn / $nameAr";
    }
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }

  Category({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.image,
    required this.imageUrl,
    this.entityType = 'category',
    this.children = const [],
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    var childrenList = <Category>[];
    if (json['children'] != null) {
      json['children'].forEach((v) {
        childrenList.add(Category.fromJson(v));
      });
    }

    return Category(
      id: _toInt(json['id']),
      nameAr: _sanitizeName(json['name_ar'] ?? json['name']),
      nameEn: _sanitizeName(json['name_en'] ?? json['name']),
      image: (json['image'] ?? json['image_url'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? json['image'] ?? '').toString(),
      entityType: (json['__entity_type'] ?? json['entity_type'] ?? 'category')
          .toString(),
      children: childrenList,
    );
  }
}

class Product {
  final int id;
  final String nameAr;
  final String nameEn;
  final String image;
  final int categoryId;
  final String entityType;
  final String? typeMachineName;

  Product({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.image,
    required this.categoryId,
    this.entityType = 'product',
    this.typeMachineName,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawTypeMachineName =
        json['type_machine_name'] ?? json['typeMachineName'];
    final modelJson = json['model'];
    final brandJson = modelJson is Map<String, dynamic> ? modelJson['brand'] : null;
    final isModelEntity =
        json.containsKey('brand_id') && !json.containsKey('model_id');
    return Product(
      id: _toInt(json['id']),
      nameAr: _sanitizeName(json['name_ar'] ?? json['name']),
      nameEn: _sanitizeName(json['name_en'] ?? json['name']),
      image: (json['image_url'] ?? json['image'] ?? '').toString(),
      categoryId: _toInt(
        json['category_id'] ??
            (brandJson is Map<String, dynamic> ? brandJson['category_id'] : null),
      ),
      entityType: isModelEntity ? 'model' : 'product',
      typeMachineName: rawTypeMachineName?.toString(),
    );
  }
}

class ProductItem {
  final int id;
  final int productId;
  final String nameAr;
  final String nameEn;
  final String imageUrl;
  final String sjcUrl;
  final String pltUrl;

  ProductItem({
    required this.id,
    required this.productId,
    required this.nameAr,
    required this.nameEn,
    required this.imageUrl,
    required this.sjcUrl,
    required this.pltUrl,
  });

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final fileUrl =
        (json['FileUrl'] ??
                json['file_url'] ??
                json['fileUrl'] ??
                json['sjc_url'] ??
                json['plt_url'] ??
                json['file'] ??
                '')
            .toString();

    return ProductItem(
      id: _toInt(json['id']),
      productId: _toInt(json['product_id'] ?? json['id']),
      nameAr: _sanitizeName(json['name_ar'] ?? json['name']),
      nameEn: _sanitizeName(json['name_en'] ?? json['name']),
      imageUrl: (json['image_url'] ?? json['image'] ?? '').toString(),
      sjcUrl: fileUrl,
      pltUrl: fileUrl,
    );
  }
}

class ProductDetail {
  final int id;
  final String nameAr;
  final String nameEn;
  final String detailIcon;
  final String file;
  final String membraneSize;

  ProductDetail({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.detailIcon,
    required this.file,
    required this.membraneSize,
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    return ProductDetail(
      id: json['id'] ?? 0,
      nameAr: _sanitizeName(json['name_ar']),
      nameEn: _sanitizeName(json['name_en']),
      detailIcon:
          json['image'] ?? '', // Note: JSON key is 'image' in detail response
      file: json['file'] ?? '',
      membraneSize: json['membrane_size'] ?? '',
    );
  }
}

class Good {
  final int id;
  final String nameAr;
  final String nameEn;
  final String image;
  final String? descriptionAr;
  final String? descriptionEn;
  final String price;
  final String? priceAfterDiscount;
  final int stock;
  final int isActive;
  final String createdAt;
  final String updatedAt;

  Good({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.image,
    this.descriptionAr,
    this.descriptionEn,
    required this.price,
    this.priceAfterDiscount,
    required this.stock,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Good.fromJson(Map<String, dynamic> json) {
    return Good(
      id: json['id'] ?? 0,
      nameAr: _sanitizeName(json['name_ar']),
      nameEn: _sanitizeName(json['name_en']),
      image: json['image'] ?? '',
      descriptionAr: json['description_ar'],
      descriptionEn: json['description_en'],
      price: json['price']?.toString() ?? '0.00',
      priceAfterDiscount: json['price_after_discount']?.toString(),
      stock: json['stock'] ?? 0,
      isActive: json['is_active'] ?? 1,
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

class GoodsPaginationResponse {
  final int currentPage;
  final List<Good> data;
  final String firstPageUrl;
  final int? from;
  final int lastPage;
  final String lastPageUrl;
  final String? nextPageUrl;
  final String path;
  final int perPage;
  final String? prevPageUrl;
  final int? to;
  final int total;

  GoodsPaginationResponse({
    required this.currentPage,
    required this.data,
    required this.firstPageUrl,
    this.from,
    required this.lastPage,
    required this.lastPageUrl,
    this.nextPageUrl,
    required this.path,
    required this.perPage,
    this.prevPageUrl,
    this.to,
    required this.total,
  });

  factory GoodsPaginationResponse.fromJson(Map<String, dynamic> json) {
    final dataJson = json['data'] as Map<String, dynamic>;
    final goodsList = (dataJson['data'] as List)
        .map((item) => Good.fromJson(item))
        .toList();

    return GoodsPaginationResponse(
      currentPage: dataJson['current_page'] ?? 1,
      data: goodsList,
      firstPageUrl: dataJson['first_page_url'] ?? '',
      from: dataJson['from'],
      lastPage: dataJson['last_page'] ?? 1,
      lastPageUrl: dataJson['last_page_url'] ?? '',
      nextPageUrl: dataJson['next_page_url'],
      path: dataJson['path'] ?? '',
      perPage: dataJson['per_page'] ?? 20,
      prevPageUrl: dataJson['prev_page_url'],
      to: dataJson['to'],
      total: dataJson['total'] ?? 0,
    );
  }
}

class DistributorRequest {
  final int id;
  final int userId;
  final int distributorId;
  final String status;
  final String createdAt;
  final String updatedAt;
  final OrderUser? user;

  DistributorRequest({
    required this.id,
    required this.userId,
    required this.distributorId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.user,
  });

  factory DistributorRequest.fromJson(Map<String, dynamic> json) {
    return DistributorRequest(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      distributorId: json['distributor_id'] ?? 0,
      status: json['status'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      user: json['user'] != null ? OrderUser.fromJson(json['user']) : null,
    );
  }
}

class Order {
  final int id;
  final int userId;
  final String totalPrice;
  final String status;
  final String createdAt;
  final String updatedAt;
  final List<OrderItem> items;
  final OrderUser? user;

  Order({
    required this.id,
    required this.userId,
    required this.totalPrice,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.user,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    var itemsList = <OrderItem>[];
    if (json['items'] != null) {
      json['items'].forEach((v) {
        itemsList.add(OrderItem.fromJson(v));
      });
    }

    return Order(
      id: json['id'] ?? 0,
      userId: json['user_id'] ?? 0,
      totalPrice: json['total_price']?.toString() ?? '0.00',
      status: json['status'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      items: itemsList,
      user: json['user'] != null ? OrderUser.fromJson(json['user']) : null,
    );
  }
}

class OrderUser {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final DistributorInfo? distributor;

  OrderUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.distributor,
  });

  factory OrderUser.fromJson(Map<String, dynamic> json) {
    return OrderUser(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      distributor: json['distributor'] != null
          ? DistributorInfo.fromJson(json['distributor'])
          : null,
    );
  }
}

class OrderItem {
  final int id;
  final int orderId;
  final int goodId;
  final int quantity;
  final String price;
  final String createdAt;
  final String updatedAt;
  final Good? good;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.goodId,
    required this.quantity,
    required this.price,
    required this.createdAt,
    required this.updatedAt,
    this.good,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] ?? 0,
      orderId: json['order_id'] ?? 0,
      goodId: json['good_id'] ?? 0,
      quantity: json['quantity'] ?? 0,
      price: json['price']?.toString() ?? '0.00',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      good: json['good'] != null ? Good.fromJson(json['good']) : null,
    );
  }
}

class OrdersPaginationResponse {
  final int currentPage;
  final List<Order> data;
  final String firstPageUrl;
  final int? from;
  final int lastPage;
  final String lastPageUrl;
  final String? nextPageUrl;
  final String path;
  final int perPage;
  final String? prevPageUrl;
  final int? to;
  final int total;

  OrdersPaginationResponse({
    required this.currentPage,
    required this.data,
    required this.firstPageUrl,
    this.from,
    required this.lastPage,
    required this.lastPageUrl,
    this.nextPageUrl,
    required this.path,
    required this.perPage,
    this.prevPageUrl,
    this.to,
    required this.total,
  });

  factory OrdersPaginationResponse.fromJson(Map<String, dynamic> json) {
    // Note: In the user JSON, data.data contains the list
    final dataRoot = json['data'] as Map<String, dynamic>;
    final ordersList = (dataRoot['data'] as List)
        .map((item) => Order.fromJson(item))
        .toList();

    return OrdersPaginationResponse(
      currentPage: dataRoot['current_page'] ?? 1,
      data: ordersList,
      firstPageUrl: dataRoot['first_page_url'] ?? '',
      from: dataRoot['from'],
      lastPage: dataRoot['last_page'] ?? 1,
      lastPageUrl: dataRoot['last_page_url'] ?? '',
      nextPageUrl: dataRoot['next_page_url'],
      path: dataRoot['path'] ?? '',
      perPage: dataRoot['per_page'] ?? 10,
      prevPageUrl: dataRoot['prev_page_url'],
      to: dataRoot['to'],
      total: dataRoot['total'] ?? 0,
    );
  }
}

class WareHouse {
  final int id;
  final int distributorId;
  final int goodId;
  final int stock;

  WareHouse({
    required this.id,
    required this.distributorId,
    required this.goodId,
    required this.stock,
  });

  factory WareHouse.fromJson(Map<String, dynamic> json) {
    return WareHouse(
      id: json['id'] ?? 0,
      distributorId: json['distributor_id'] ?? 0,
      goodId: json['good_id'] ?? 0,
      stock: json['stock'] ?? 0,
    );
  }
}

class DistributorInfo {
  final int id;
  final String name;
  final List<WareHouse> wareHouses;

  DistributorInfo({
    required this.id,
    required this.name,
    this.wareHouses = const [],
  });

  factory DistributorInfo.fromJson(Map<String, dynamic> json) {
    var wareHousesList = <WareHouse>[];
    if (json['ware_houses'] != null) {
      json['ware_houses'].forEach((v) {
        wareHousesList.add(WareHouse.fromJson(v));
      });
    }

    return DistributorInfo(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      wareHouses: wareHousesList,
    );
  }
}

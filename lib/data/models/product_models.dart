class Category {
  final int id;
  final String nameAr;
  final String nameEn;
  final String image;
  final String imageUrl;

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
      id: json['id'] ?? 0,
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
      image: json['image'] ?? '',
      imageUrl: json['image_url'] ?? '',
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

  Product({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.image,
    required this.categoryId,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
      image: json['image'] ?? '',
      categoryId: json['category_id'] ?? 0,
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
    return ProductItem(
      id: json['id'] ?? 0,
      productId: json['product_id'] ?? 0,
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
      imageUrl: json['image_url'] ?? '',
      sjcUrl: json['sjc_url'] ?? '',
      pltUrl: json['plt_url'] ?? '',
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
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
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
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
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

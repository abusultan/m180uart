class Category {
  final int id;
  final String name;
  final String image;
  final String imageUrl;

  final List<Category> children;

  Category({
    required this.id,
    required this.name,
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
      name:
          json['name_en'] ??
          json['name_ar'] ??
          '', // Fallback to localized name if needed logic
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

class Representative {
  final int id;
  final String name;
  final String nameAr;
  final String nameEn;

  const Representative({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.nameEn,
  });

  String get displayName {
    if (name.isNotEmpty) return name;
    if (nameEn.isNotEmpty && nameAr.isNotEmpty) {
      return "$nameEn / $nameAr";
    }
    return nameEn.isNotEmpty ? nameEn : nameAr;
  }

  factory Representative.fromJson(Map<String, dynamic> json) {
    return Representative(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      nameAr: json['name_ar'] ?? '',
      nameEn: json['name_en'] ?? '',
    );
  }
}

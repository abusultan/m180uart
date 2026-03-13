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
      id: _toInt(json['id']),
      name: json['name']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      nameEn: json['name_en']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

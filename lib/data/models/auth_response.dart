class User {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final int remainingPieces;
  final String? representativeName;
  final String? distributorName;
  final int? representativeId;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.remainingPieces,
    this.representativeName,
    this.distributorName,
    this.representativeId,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: _toInt(json['id']),
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      remainingPieces: _toInt(json['remaining_pieces']),
      representativeName:
          json['representative_name'] ??
          json['mandob_name'] ??
          json['rep_name'] ??
          json['representative'],
      distributorName:
          json['distributor_name'] ??
          json['distributor'] ??
          json['dealer_name'] ??
          json['supplier_name'],
      representativeId:
          _toNullableInt(
            json['representative_id'] ??
                json['distributor_id'] ??
                json['mandob_id'] ??
                json['rep_id'],
          ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class LoginResponse {
  final bool success;
  final String message;
  final User? user;
  final String token;

  LoginResponse({
    required this.success,
    required this.message,
    this.user,
    required this.token,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final success = json['success'] == true;
    final msg = json['message']?.toString() ?? '';
    final nestedData = json['data'] is Map<String, dynamic>
        ? json['data'] as Map<String, dynamic>
        : json['data'] is Map
        ? Map<String, dynamic>.from(json['data'] as Map)
        : <String, dynamic>{};

    final userJson = nestedData['user'] is Map<String, dynamic>
        ? nestedData['user'] as Map<String, dynamic>
        : nestedData['user'] is Map
        ? Map<String, dynamic>.from(nestedData['user'] as Map)
        : json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : null;

    final usr = userJson == null ? null : User.fromJson(userJson);
    final tkn =
        nestedData['token']?.toString() ??
        json['token']?.toString() ??
        '';

    return LoginResponse(success: success, message: msg, user: usr, token: tkn);
  }
}

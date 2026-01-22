class User {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final int remainingPieces;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.remainingPieces,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      remainingPieces: json['remaining_pieces'] ?? 0,
    );
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
    bool success = json['success'] ?? false;
    String msg = json['message'] ?? '';

    User? usr;
    String tkn = '';

    if (json['data'] != null) {
      if (json['data']['user'] != null) {
        usr = User.fromJson(json['data']['user']);
      }
      tkn = json['data']['token'] ?? '';
    }

    return LoginResponse(success: success, message: msg, user: usr, token: tkn);
  }
}

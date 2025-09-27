class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String lastName;
  final String role;
  final String? username; // Stable unique handle e.g. "edrick123"
  final String? fcmToken;

  AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.lastName,
    required this.role,
    this.username,
    this.fcmToken,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      lastName: data['lastName'] ?? '',
      role: data['role'] ?? '',
      username: data['username'],
      fcmToken: data['fcmToken'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'lastName': lastName,
      'role': role,
      'username': username,
      'fcmToken': fcmToken,
    };
  }
}

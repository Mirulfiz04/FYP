/// A user's profile row from the Supabase `profiles` table.
class UserProfile {
  final String id;
  final String? name;
  final String? email;
  final String? role;
  final int? age;
  final String? gender;
  final String? contactNumber;
  final String? location;
  final String? avatarUrl;
  final String? status; // active | blocked
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    this.name,
    this.email,
    this.role,
    this.age,
    this.gender,
    this.contactNumber,
    this.location,
    this.avatarUrl,
    this.status,
    this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isBlocked => status == 'blocked';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      role: json['role'] as String?,
      age: (json['age'] as num?)?.toInt(),
      gender: json['gender'] as String?,
      contactNumber: json['contact_number'] as String?,
      location: json['location'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      status: json['status'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  /// Fields the user can edit from Settings (id is supplied separately).
  Map<String, dynamic> toEditableJson() => {
        'name': name,
        'age': age,
        'gender': gender,
        'contact_number': contactNumber,
        'location': location,
      };

  UserProfile copyWith({
    String? name,
    String? email,
    String? role,
    int? age,
    String? gender,
    String? contactNumber,
    String? location,
    String? avatarUrl,
    String? status,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      contactNumber: contactNumber ?? this.contactNumber,
      location: location ?? this.location,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

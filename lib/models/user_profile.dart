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
  final DateTime? updatedAt;
  final String? displayName;

  // Registration / demographic fields (collected at sign-up).
  final String? ageGroup;
  final String? userCategory; // Student | Employee | Other
  final String? userCategoryOther; // free text when userCategory == 'Other'
  final String? monitoringGoal;
  final String? notificationPref; // All | Important only | None
  final bool privacyConsent;
  final bool researchAck;

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
    this.updatedAt,
    this.displayName,
    this.ageGroup,
    this.userCategory,
    this.userCategoryOther,
    this.monitoringGoal,
    this.notificationPref,
    this.privacyConsent = false,
    this.researchAck = false,
  });

  bool get isAdmin => role == 'admin';
  bool get isBlocked => status == 'blocked';
  bool get isInactive => status == 'inactive';

  /// True when an administrator has disabled the account (blocked OR
  /// deactivated). Such accounts are kept out of the app at sign-in.
  bool get isDisabled => isBlocked || isInactive;

  /// Best human label: display name, else full name, else email.
  String get displayLabel {
    if (displayName?.trim().isNotEmpty == true) return displayName!.trim();
    if (name?.trim().isNotEmpty == true) return name!.trim();
    return email ?? 'MEDS user';
  }

  /// Up to two initials for the default avatar.
  String get initials {
    final source =
        (name?.trim().isNotEmpty == true) ? name!.trim() : (email ?? '');
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return source[0].toUpperCase();
  }

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
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      displayName: json['display_name'] as String?,
      ageGroup: json['age_group'] as String?,
      userCategory: json['user_category'] as String?,
      userCategoryOther: json['user_category_other'] as String?,
      monitoringGoal: json['monitoring_goal'] as String?,
      notificationPref: json['notification_pref'] as String?,
      privacyConsent: json['privacy_consent'] as bool? ?? false,
      researchAck: json['research_ack'] as bool? ?? false,
    );
  }

  /// Fields the user can edit from Settings (id is supplied separately).
  /// Note: registration-only fields (consent, demographics) are intentionally
  /// omitted so a Settings save never overwrites them.
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
    DateTime? updatedAt,
    String? displayName,
    String? ageGroup,
    String? userCategory,
    String? userCategoryOther,
    String? monitoringGoal,
    String? notificationPref,
    bool? privacyConsent,
    bool? researchAck,
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
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      ageGroup: ageGroup ?? this.ageGroup,
      userCategory: userCategory ?? this.userCategory,
      userCategoryOther: userCategoryOther ?? this.userCategoryOther,
      monitoringGoal: monitoringGoal ?? this.monitoringGoal,
      notificationPref: notificationPref ?? this.notificationPref,
      privacyConsent: privacyConsent ?? this.privacyConsent,
      researchAck: researchAck ?? this.researchAck,
    );
  }
}

import 'dart:io';

import '../models/user_profile.dart';
import 'auth_service.dart';

/// Profile data access. Keeps auth/database calls out of the UI + view model.
abstract class ProfileRepository {
  Future<UserProfile> load();
  Future<void> save(UserProfile profile);
  Future<String> uploadAvatar(File file);
  Future<void> deleteAvatar();
}

/// Backed by Supabase via [AuthService].
class SupabaseProfileRepository implements ProfileRepository {
  final AuthService _auth;
  SupabaseProfileRepository([AuthService? auth]) : _auth = auth ?? AuthService();

  @override
  Future<UserProfile> load() => _auth.loadProfile();

  @override
  Future<void> save(UserProfile profile) => _auth.updateProfile(profile);

  @override
  Future<String> uploadAvatar(File file) => _auth.uploadAvatar(file);

  @override
  Future<void> deleteAvatar() => _auth.deleteAvatar();
}

/// In-memory profile for demos / tests, behind the same interface.
class SampleProfileRepository implements ProfileRepository {
  UserProfile _profile;

  SampleProfileRepository([UserProfile? profile])
      : _profile = profile ??
            const UserProfile(
              id: 'sample-user',
              name: 'Amirul Hakim',
              displayName: 'Amirul',
              email: 'amirulhakim@email.com',
              ageGroup: '18–24',
              gender: 'Male',
              userCategory: 'Student',
              monitoringGoal: 'Stress monitoring',
            );

  @override
  Future<UserProfile> load() async => _profile;

  @override
  Future<void> save(UserProfile profile) async => _profile = profile;

  @override
  Future<String> uploadAvatar(File file) async {
    _profile = _profile.copyWith(avatarUrl: file.path);
    return file.path;
  }

  @override
  Future<void> deleteAvatar() async =>
      _profile = _profile.copyWith(avatarUrl: '');
}

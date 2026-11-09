import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

/// Wraps Supabase auth, the `profiles` table, and the `avatars` storage bucket.
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => _client.auth.currentSession != null;

  /// Registers a new account. The extra profile fields are stored in the
  /// auth user's metadata so the database trigger can populate `profiles`
  /// even before the email is confirmed.
  ///
  /// Returns true if a session was created immediately (email confirmation
  /// is off); false means the user must confirm their email first.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required bool privacyConsent,
    required bool researchAck,
    String? ageGroup,
    String? gender,
    String? userCategory,
    String? userCategoryOther,
    String? monitoringGoal,
    String? notificationPref,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': name,
        'age_group': ageGroup,
        'gender': gender,
        'user_category': userCategory,
        'user_category_other': userCategoryOther,
        'monitoring_goal': monitoringGoal,
        'notification_pref': notificationPref,
        'privacy_consent': privacyConsent,
        'research_ack': researchAck,
      },
    );
    return res.session != null;
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Signs out this account on every device/session.
  Future<void> signOutEverywhere() =>
      _client.auth.signOut(scope: SignOutScope.global);

  /// Sends a password-reset email to [email] (used by the "Forgot Password?"
  /// link on the login screen and "Change password" in Privacy & Security).
  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email);

  /// Persists the editable Profile fields (Edit Profile screen). Only writes
  /// the columns the user can change, preserving everything else.
  Future<void> updateProfile(UserProfile profile) async {
    final user = currentUser!;
    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      'name': profile.name,
      'display_name': profile.displayName,
      'age_group': profile.ageGroup,
      'gender': profile.gender,
      'user_category': profile.userCategory,
      'monitoring_goal': profile.monitoringGoal,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Deletes the user's session history (sessions + readings). Requires the
  /// delete RLS policies in supabase_setup_profile_extras.sql.
  Future<void> deleteSessionHistory() async {
    final user = currentUser!;
    await _client.from('emotion_readings').delete().eq('user_id', user.id);
    await _client.from('detection_sessions').delete().eq('user_id', user.id);
  }

  /// Removes all of the user's data (readings, sessions, notifications, avatar,
  /// profile row) then signs out. The auth login itself can only be removed
  /// server-side with a service-role key, so the user is signed out here.
  Future<void> deleteAccountData() async {
    final user = currentUser!;
    await _client.from('notifications').delete().eq('user_id', user.id);
    await _client.from('emotion_readings').delete().eq('user_id', user.id);
    await _client.from('detection_sessions').delete().eq('user_id', user.id);
    await _removeAvatarFiles(user.id);
    await _client.from('profiles').delete().eq('id', user.id);
    await signOut();
  }

  /// Loads the current user's profile, creating a minimal row if none exists
  /// (resilient even if the database trigger is not set up).
  Future<UserProfile> loadProfile() async {
    final user = currentUser!;
    final data =
        await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (data != null) return UserProfile.fromJson(data);

    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
    });
    return UserProfile(id: user.id, email: user.email);
  }

  Future<void> saveProfile(UserProfile profile) async {
    final user = currentUser!;
    await _client.from('profiles').upsert({
      'id': user.id,
      'email': user.email,
      ...profile.toEditableJson(),
    });
  }

  /// Uploads [file] as the user's avatar and returns a cache-busted public URL.
  Future<String> uploadAvatar(File file) async {
    final user = currentUser!;
    final ext = file.path.split('.').last.toLowerCase();
    final objectPath = '${user.id}/avatar.$ext';

    // Clear any previous avatar(s) so we don't leave orphaned files.
    await _removeAvatarFiles(user.id);

    await _client.storage.from('avatars').upload(
          objectPath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    final url = _client.storage.from('avatars').getPublicUrl(objectPath);
    final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

    await _client
        .from('profiles')
        .upsert({'id': user.id, 'email': user.email, 'avatar_url': bustedUrl});
    return bustedUrl;
  }

  Future<void> deleteAvatar() async {
    final user = currentUser!;
    await _removeAvatarFiles(user.id);
    await _client
        .from('profiles')
        .upsert({'id': user.id, 'email': user.email, 'avatar_url': null});
  }

  Future<void> _removeAvatarFiles(String userId) async {
    final files = await _client.storage.from('avatars').list(path: userId);
    if (files.isEmpty) return;
    await _client
        .storage
        .from('avatars')
        .remove(files.map((f) => '$userId/${f.name}').toList());
  }
}

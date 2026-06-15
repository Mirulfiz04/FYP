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
    int? age,
    String? gender,
    String? contactNumber,
    String? location,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'name': name,
        'age': age,
        'gender': gender,
        'contact_number': contactNumber,
        'location': location,
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

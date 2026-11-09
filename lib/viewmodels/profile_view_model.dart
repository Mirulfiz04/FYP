import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/profile_repository.dart';

/// Holds the current user's profile and the load/save lifecycle. A
/// [ChangeNotifier] like the app's other controllers; the UI listens with
/// [ListenableBuilder]. Auth/database access stays in the repository.
class ProfileViewModel extends ChangeNotifier {
  final ProfileRepository repository;
  ProfileViewModel({required this.repository});

  bool _loading = true;
  bool _saving = false;
  String? _error;
  UserProfile? _profile;

  bool get loading => _loading;
  bool get saving => _saving;
  String? get error => _error;
  UserProfile? get profile => _profile;

  /// Shared e-mail format check (also used by the Edit Profile form + tests).
  static bool emailIsValid(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _profile = await repository.load();
      _loading = false;
      notifyListeners();
    } catch (_) {
      _error = 'Could not load your profile.';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Persists [updated]; reloads from the source on success so the header
  /// reflects the change immediately. Returns true on success.
  Future<bool> save(UserProfile updated) async {
    _saving = true;
    notifyListeners();
    try {
      await repository.save(updated);
      _profile = await repository.load();
      _saving = false;
      notifyListeners();
      return true;
    } catch (_) {
      _saving = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadAvatar(File file) async {
    try {
      final url = await repository.uploadAvatar(file);
      _profile = _profile?.copyWith(avatarUrl: url);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeAvatar() async {
    try {
      await repository.deleteAvatar();
      _profile = await repository.load();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}

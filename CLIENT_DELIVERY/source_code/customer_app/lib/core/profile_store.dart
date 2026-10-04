import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'supabase_config.dart';

class ProfileStore extends ChangeNotifier {
  static final ProfileStore _instance = ProfileStore._internal();
  factory ProfileStore() => _instance;
  ProfileStore._internal();

  Map<String, dynamic>? _profile;

  Map<String, dynamic>? get profile => _profile;
  bool get codAllowed => _profile?['cod_allowed'] ?? true;
  String get accountStatus => _profile?['account_status'] ?? 'Active';

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('cached_profile');
      if (data != null) {
        _profile = jsonDecode(data);
        notifyListeners();
        debugPrint(">>> [PROFILE STORE] Loaded from cache");
      }
    } catch (e) {
      debugPrint("Error loading profile from disk: $e");
    }
  }

  Future<void> _saveToDisk() async {
    try {
      if (_profile == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_profile', jsonEncode(_profile));
    } catch (e) {
      debugPrint("Error saving profile to disk: $e");
    }
  }

  void sync(Map<String, dynamic> data) {
    _profile = data;
    _saveToDisk();
    notifyListeners();
  }

  void updateField(String key, dynamic value) {
    if (_profile != null) {
      _profile![key] = value;
      _saveToDisk();
      notifyListeners();
    }
  }

  Future<void> fetchProfile(String uid) async {
    try {
      final res = await SupabaseConfig.client
          .from('customer_profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (res != null) {
        sync(res);
      }
    } catch (e) {
      debugPrint("Fetch Profile Error: $e");
    }
  }

  void clear() {
    _profile = null;
    notifyListeners();
  }
}

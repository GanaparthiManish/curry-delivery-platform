import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'supabase_config.dart';

/// SystemStore — singleton that holds platform-wide fees & settings.
/// It fetches from Supabase `app_settings` on startup AND subscribes
/// to real-time changes so that the customer app INSTANTLY reflects
/// any update made by the admin in the Command Center.
class SystemStore extends ChangeNotifier {
  static final SystemStore _instance = SystemStore._internal();
  factory SystemStore() => _instance;
  SystemStore._internal();

  // ── Default values (shown until real data loads) ──────────────────
  double _deliveryFee = 0.0;
  double _platformFee = 0.0;
  double _taxRate = 0.0;
  bool _codEnabled = true;
  bool _maintenanceMode = false;

  double get deliveryFee => _deliveryFee;
  double get platformFee => _platformFee;
  double get taxRate => _taxRate;
  bool get codEnabled => _codEnabled;
  bool get maintenanceMode => _maintenanceMode;

  bool _isLoaded = false;
  RealtimeChannel? _channel;

  // ── Public API ─────────────────────────────────────────────────────

  /// Call once at app startup (e.g. in main.dart after Supabase.initialize).
  Future<void> init() async {
    await loadFromDisk();   // fast — use cached value if available
    await fetchSystemConfig(); // then fetch fresh from server
    _subscribeRealtime();   // keep listening for admin changes
  }

  // ── Fetch from Supabase ───────────────────────────────────────────
  Future<void> fetchSystemConfig() async {
    try {
      final res = await SupabaseConfig.client
          .from('app_settings')
          .select('value')
          .eq('key', 'system_config')
          .maybeSingle();

      if (res != null && res['value'] != null) {
        _applyConfig(Map<String, dynamic>.from(res['value'] as Map));
      }
    } catch (e) {
      debugPrint('>>> [SYSTEM STORE] Fetch Error: $e');
    }
  }

  // ── Real-time subscription ─────────────────────────────────────────
  void _subscribeRealtime() {
    // Avoid duplicate channels
    _channel?.unsubscribe();

    _channel = SupabaseConfig.client
        .channel('system_config_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'key',
            value: 'system_config',
          ),
          callback: (payload) {
            debugPrint('>>> [SYSTEM STORE] Realtime update received!');
            final newRecord = payload.newRecord;
            if (newRecord.isNotEmpty && newRecord['value'] != null) {
              _applyConfig(Map<String, dynamic>.from(newRecord['value'] as Map));
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('>>> [SYSTEM STORE] Realtime status: $status error: $error');
        });
  }

  // ── Apply config values and notify ────────────────────────────────
  void _applyConfig(Map<String, dynamic> config) {
    _deliveryFee = (config['deliveryFee'] ?? 0.0).toDouble();
    _platformFee = (config['platformFee'] ?? 0.0).toDouble();
    _taxRate = (config['taxRate'] ?? 0.0).toDouble();
    _codEnabled = config['codEnabled'] ?? true;
    _maintenanceMode = config['maintenanceMode'] ?? false;

    _isLoaded = true;
    notifyListeners();

    // Cache to disk for next cold start
    _saveToDisk();

    debugPrint(
      '>>> [SYSTEM STORE] Config applied: '
      'delivery=₹$_deliveryFee platform=₹$_platformFee gst=$_taxRate%',
    );
  }

  // ── Disk cache ─────────────────────────────────────────────────────
  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_system_config',
        jsonEncode({
          'deliveryFee': _deliveryFee,
          'platformFee': _platformFee,
          'taxRate': _taxRate,
          'codEnabled': _codEnabled,
          'maintenanceMode': _maintenanceMode,
        }),
      );
    } catch (e) {
      debugPrint('>>> [SYSTEM STORE] Disk Save Error: $e');
    }
  }

  Future<void> loadFromDisk() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('cached_system_config');
      if (data != null) {
        _applyConfig(jsonDecode(data) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('>>> [SYSTEM STORE] Disk Load Error: $e');
    }
  }

  // ── Cleanup ────────────────────────────────────────────────────────
  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

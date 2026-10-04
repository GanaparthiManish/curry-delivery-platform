import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide debugPrint;

import 'cart_state.dart';
import 'order_store.dart';
import 'wallet_store.dart';
import 'profile_store.dart';
import 'address_store.dart';
import 'favorite_store.dart';
import 'notification_store.dart';
import 'services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:shared_preferences/shared_preferences.dart';

import 'system_store.dart';

class SupabaseConfig {
  static const String url = 'https://dxqcruvarqgnscenixzf.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

  // 🖼️ UNIVERSAL IMAGE HELPER
  static String imageUrl(dynamic path, {String? bucket = 'images'}) {
    final String p =
        (path ?? "").toString().trim().replaceAll('"', '').replaceAll("'", "");

    if (p.isEmpty || p == "null") {
      // 🎲 Better random food fallback to avoid "broken" look
      final fallbacks = [
        "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&q=80",
        "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=600&q=80",
        "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&q=80",
        "https://images.unsplash.com/photo-1473093226795-af9932fe5856?w=600&q=80"
      ];
      return fallbacks[path.hashCode.abs() % fallbacks.length];
    }

    if (p.startsWith('http')) return p;
    // Handle Supabase bucket relative paths
    final cleanPath = p.startsWith('/') ? p.substring(1) : p;
    return "$url/storage/v1/object/public/$bucket/$cleanPath";
  }

  static SharedPreferences? _prefs;

  static Future<void> initialize() async {
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        debug: developerMode,
      );
      debugPrint(">>> [SUPABASE] Connectivity: OK");
    } catch (e) {
      debugPrint(">>> [SUPABASE] Initialization Warning: $e");
    }
  }

  // 🚀 EARLY SESSION LOAD - Pure SharedPrefs ONLY. No Supabase, no bootstrap.
  // bootstrap() is called by RootDecision after full Supabase initialization.
  static Future<void> loadSessionFromDisk() async {
    try {
      debugPrint('>>> [BOOT] Checking disk for session...');
      _prefs ??= await SharedPreferences.getInstance();
      await SystemStore().loadFromDisk();
      SystemStore().init(); // Start real-time subscription early
      final String? savedUid = _prefs?.getString('forced_uid');
      debugPrint('>>> [BOOT] Disk UID: $savedUid');
      if (savedUid != null && savedUid.isNotEmpty) {
        _forcedUid = savedUid;
        _sessionNotifier.value = savedUid;
        debugPrint(
            '>>> [BOOT] Session set: $_forcedUid (upgrade happens after init)');
      } else {
        debugPrint('>>> [BOOT] No session. User must login.');
      }
    } catch (e) {
      debugPrint('>>> [BOOT] ERROR: $e');
    }
  }

  static bool developerMode = false;
  static String? _forcedUid;

  static String? get currentUid {
    final uid = _forcedUid ??
        client.auth.currentUser?.id ??
        FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      debugPrint(
          ">>> [AUTH] currentUid Resolved: $uid (Source: ${_forcedUid != null ? 'FORCED' : 'SINGLETON'})");
    }
    return uid;
  }

  // Legacy compatibility getters
  static String? get forcedUserId => currentUid;
  static final ValueNotifier<String?> _sessionNotifier =
      ValueNotifier<String?>(null);
  static ValueListenable<String?> get sessionUser => _sessionNotifier;

  // Robust client getter that won't crash the app if accessed early
  static SupabaseClient get client {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint(">>> [CRITICAL] Requesting client BEFORE Init. Using fallback.");
      return SupabaseClient(url, anonKey);
    }
  }

  static Future<void> logout() async {
    debugPrint(">>> PERFORMING GLOBAL LOGOUT");
    try {
      // 1. Core Auth
      _forcedUid = null;
      _sessionNotifier.value = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('forced_uid');

      await client.auth.signOut();
      await FirebaseAuth.instance.signOut();

      // 2. Clear Stores
      GlobalCart().clear();
      OrderStore().clear();
      ProfileStore().clear();
      WalletStore().clear();
      AddressStore().clear();
      NotificationStore().reset();

      // 3. Deactivate Realtime
      AppRealtimeHub.deactivate();

      debugPrint(">>> LOGOUT COMPLETE");
    } catch (e) {
      debugPrint(">>> LOGOUT FAULT: $e");
    }
  }

  // 🚀 RE-SYNC & RE-INITIALIZE DATA STREAMS
  static Future<void> bootstrap({bool forceRestartHub = false}) async {
    final String? uid = currentUid;
    if (uid == null) {
      debugPrint(">>> [BOOTSTRAP] ABORTED: No user ID");
      return;
    }
    debugPrint(">>> [BOOTSTRAP] SYNCING ALL STORES FOR: $uid");

    // 1. Activate Live Data
    if (forceRestartHub) {
      AppRealtimeHub.deactivate();
      // 🛡️ IDENTITY SWITCH: Clear stale data from previous user
      OrderStore().clear();
    }
    AppRealtimeHub.activate(uid);

    // 2. Deep Refresh Stores - MOVE TO BACKGROUND to avoid blocking UI transition
    _runBackgroundSync(uid);
  }

  static void _runBackgroundSync(String uid) {
    Future.wait<dynamic>([
      SystemStore().init(), // Fetches + activates realtime subscription
      ProfileStore().fetchProfile(uid).timeout(const Duration(seconds: 5)),
      OrderStore().fetchOrders().timeout(const Duration(seconds: 10)),
      WalletStore().fetchBalance().timeout(const Duration(seconds: 5)),
      // Sync Favorites
      client
          .from('user_favorites')
          .select()
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 5))
          .then((favs) => FavoriteStore.sync(List<dynamic>.from(favs as List)))
          .catchError((e) => debugPrint("FAVORITE AUTO-SYNC ERROR: $e")),
      // Sync Addresses
      client
          .from('user_addresses')
          .select()
          .eq('user_id', uid)
          .timeout(const Duration(seconds: 5))
          .then((addrs) =>
              AddressStore().sync(List<Map<String, dynamic>>.from(addrs as List)))
          .catchError((e) => debugPrint("ADDRESS AUTO-SYNC ERROR: $e")),
      // Sync Notifications
      client
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false)
          .then((res) => NotificationStore().setCount((res as List).length))
          .catchError((e) => debugPrint("NOTIF SYNC ERROR: $e")),
    ]).then((_) {
      debugPrint(">>> [BOOTSTRAP] Background Sync completed successfully.");
    }).catchError((e) {
      debugPrint(">>> [BOOTSTRAP] Background Sync completed with some warnings: $e");
    });
  }

  // 🔐 SAVE SESSION HELPERS FOR PERSISTENCE
  static Future<void> saveSession(String userId) async {
    try {
      _forcedUid = userId;
      _sessionNotifier.value = userId;

      // PERSIST TO DISK (Crucial for restart)
      _prefs ??= await SharedPreferences.getInstance();
      final success = await _prefs!.setString('forced_uid', userId);

      if (success) {
        debugPrint(">>> [DISK] Session SAVED successfully: $userId");
      } else {
        debugPrint(">>> [DISK] CRITICAL ERROR: Disk Write Failed!");
      }

      // 🏎️ INSTANT BOOT: Don't await the full store refresh
      bootstrap(forceRestartHub: true);
    } catch (e) {
      debugPrint(">>> [SESSION] Save Failed: $e");
    }
  }

  // 🆔 IDENTITY RECOVERY: Find existing user by phone to restore history
  static Future<String> findOrCreateUid(String phone) async {
    try {
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      String cleanPhone = digits;
      if (cleanPhone.startsWith('91') && cleanPhone.length == 12) {
        cleanPhone = cleanPhone.substring(2);
      } else if (cleanPhone.startsWith('0') && cleanPhone.length == 11) {
        cleanPhone = cleanPhone.substring(1);
      }
      if (cleanPhone.length > 10) cleanPhone = cleanPhone.substring(cleanPhone.length - 10);

      debugPrint('>>> [IDENTITY] Looking up phone: $cleanPhone');

      final res = await client
          .from('customer_profiles')
          .select('id')
          .eq('phone', cleanPhone)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (res != null) {
        debugPrint('>>> [IDENTITY] FOUND MASTER ID: ${res['id']}');
        return res['id'].toString();
      }

      // 🆕 Create new user record
      final newUid = 'sms_auth_$cleanPhone';
      await client
          .from('customer_profiles')
          .insert({'id': newUid, 'phone': cleanPhone}).timeout(
              const Duration(seconds: 10));
      return newUid;
    } catch (e) {
      debugPrint("FindOrCreateUid Error: $e");
      return 'sms_auth_${phone.replaceAll(RegExp(r'\D'), '')}';
    }
  }

  // 📝 PROFILE SYNC HELPER (Firebase/Supabase -> Supabase)
  static Future<Map<String, dynamic>?> syncUser(String phone,
      {String? manualUid}) async {
    final uid = manualUid ?? currentUid;
    if (uid == null) return null;

    debugPrint(">>> [SYNC] UPSERTING PROFILE: $uid ($phone)");

    try {
      final res = await client
          .from('customer_profiles')
          .upsert({
            'id': uid,
            'phone': phone
                .replaceAll(RegExp(r'\D'), '')
                .replaceFirst(RegExp(r'^91'), '')
                .replaceFirst(RegExp(r'^0'), ''),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (res != null) {
        debugPrint(">>> [SYNC] Profile data received from Supabase: $res");
        ProfileStore().sync(res);
        bootstrap(forceRestartHub: true);
        return res;
      } else {
        debugPrint(
            ">>> [SYNC] Profile UPSERT returned null - Checking existing...");
        final existing = await client
            .from('customer_profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
        if (existing != null) {
          ProfileStore().sync(existing);
          return existing;
        }
      }
    } catch (e) {
      debugPrint(">>> [SYNC] CRITICAL ERROR: $e");
    }
    return null;
  }
}

// 🌐 REALTIME HUB v8.1 - Proven stable approach
class AppRealtimeHub {
  static RealtimeChannel? _mainChannel;

  static void activate(String userId) {
    // Always recreate — allows proper channel re-init after Supabase.initialize()
    if (_mainChannel != null) {
      try {
        SupabaseConfig.client.removeChannel(_mainChannel!);
      } catch (_) {}
      _mainChannel = null;
    }

    debugPrint('>>> [HUB] ACTIVATING v8.1 FOR: $userId');

    // Build all possible user IDs for this user (master + legacy sms_auth variants)
    final List<String> userIds = [userId];
    String? phone;
    if (userId.startsWith('sms_auth_')) {
      phone = userId.replaceFirst('sms_auth_', '');
    } else {
      // If it's a UUID, we should still check if there's a phone linked to it
      // For now, we'll try to extract it from the ProfileStore if available
      final p = ProfileStore().profile;
      if (p != null && p['phone'] != null) {
        phone = p['phone'].toString();
      }
    }

    if (phone != null) {
      final clean = phone.replaceAll(RegExp(r'\D'), '');
      final short = clean.length > 10 ? clean.substring(clean.length - 10) : clean;
      
      // Expand to all known variants to ensure notifications arrive regardless of which ID the backend used
      if (!userIds.contains(short)) userIds.add(short);
      if (!userIds.contains('sms_auth_$short')) userIds.add('sms_auth_$short');
      if (!userIds.contains('sms_auth_91$short')) userIds.add('sms_auth_91$short');
    }

    debugPrint('>>> [HUB] Listening for IDs: $userIds');

    _mainChannel = SupabaseConfig.client
        .channel('app_hub_v81:$userId')

        // 🔔 NOTIFICATIONS — callback filter (works without DB publication changes)
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            callback: (payload) {
              final rec = payload.newRecord;
              final notifUserId = (rec['user_id'] ?? '').toString();
              // Match if ANY of the user's known IDs match
              final isForMe = userIds.any((id) => id == notifUserId) ||
                  notifUserId == 'BROADCAST';
              debugPrint('>>> [NOTIF] user_id=$notifUserId | forMe=$isForMe');
              if (isForMe) {
                NotificationService.showLocalNotificationDirect(
                  title: rec['title'] ?? 'Order Update',
                  body: rec['message'] ??
                      rec['body'] ??
                      'Your order status changed.',
                );
                NotificationStore().increment();
              }
            })

        // 📦 ORDERS — full real-time sync
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              final rec = payload.newRecord;
              final old = payload.oldRecord;
              
              final newStatus = rec['order_status'] ?? rec['status'];
              final oldStatus = old['order_status'] ?? old['status'];
              
              debugPrint('>>> [ORDERS] ${payload.eventType} | status: $newStatus');
              
              OrderStore().updateFromRealtime(rec.isEmpty ? old : rec);
              
              // Fallback: If status changed or it's a new order (insert), immediately show local notification!
              if (newStatus != null && newStatus != oldStatus) {
                String title = 'Order Update';
                String body = 'Your order status changed to $newStatus.';
                
                final nStat = newStatus.toString().toLowerCase();
                if (nStat == 'placed' || nStat == 'payment_pending') {
                  title = 'Order Placed! 🍽️';
                  body = 'We have received your order.';
                } else if (nStat == 'accepted') {
                  title = 'Order Accepted! 🍳';
                  body = 'The vendor is preparing your food.';
                } else if (nStat == 'preparing') {
                  title = 'Food is Cooking! 🥘';
                  body = 'Your meal is being prepared.';
                } else if (nStat == 'ready' || nStat == 'ready_for_pickup') {
                  title = 'Order Ready! 🛍️';
                  body = 'Waiting for a rider to pick it up.';
                } else if (nStat == 'dispatching' || nStat == 'picked_up' || nStat == 'out_for_delivery') {
                  title = 'Out for Delivery! 🛵';
                  body = 'Your food is on the way.';
                } else if (nStat == 'delivered') {
                  title = 'Order Delivered! 🎉';
                  body = 'Enjoy your meal!';
                } else if (nStat == 'cancelled' || nStat == 'rejected') {
                  title = 'Order Cancelled ❌';
                  body = 'Unfortunately, your order was cancelled.';
                }
                
                NotificationService.showLocalNotificationDirect(title: title, body: body);
              }
              
              NotificationStore().fetchLatestNotifications(userIds);
            })

        // 💰 WALLETS — balance updates
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'wallets',
            callback: (payload) {
              final bal = payload.newRecord['balance'];
              WalletStore()
                  .updateBalance(double.tryParse(bal.toString()) ?? 0.0);
            })

        // 📍 GPS TRACKING
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_live_tracking',
            callback: (payload) {
              OrderStore().updateLiveLocation(payload.newRecord);
            })
        .subscribe((status, [err]) {
      debugPrint(
          '>>> [HUB] Channel status: $status ${err != null ? '| $err' : ''}');
    });
  }

  static void deactivate() {
    if (_mainChannel != null) {
      try {
        SupabaseConfig.client.removeChannel(_mainChannel!);
      } catch (_) {}
      _mainChannel = null;
    }
  }
}

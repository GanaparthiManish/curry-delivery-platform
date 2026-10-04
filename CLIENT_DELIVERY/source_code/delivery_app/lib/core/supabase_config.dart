import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';

class SupabaseConfig extends ChangeNotifier {
  static final SupabaseConfig _instance = SupabaseConfig._internal();
  factory SupabaseConfig() => _instance;
  SupabaseConfig._internal();

  static SupabaseConfig get notifier => _instance;
  void notify() => notifyListeners();

  static const String url = 'https://dxqcruvarqgnscenixzf.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

  static const double _radiusKm = 50.0; // 🎯 50km localized radius


  static Future<void> initialize() async {
    await Supabase.initialize(url: url, anonKey: anonKey);
    await loadSession();
  }

  static SupabaseClient get client => Supabase.instance.client;
  static String? get forcedRiderId => client.auth.currentUser?.id;
  static Map<String, dynamic>? bootstrapData;

  // Rider's last known GPS (updated every bootstrap)
  static double? _riderLat;
  static double? _riderLng;

  static Future<void> saveSession(String userId) async {
    await bootstrap();
  }

  static Future<void> loadSession() async {
    if (client.auth.currentUser?.id != null) {
      await bootstrap();
    }
  }

  static Future<void> logout() async {
    bootstrapData = null;
    _riderLat = null;
    _riderLng = null;
    await client.auth.signOut();
    AppRealtimeHub.deactivate();
  }

  // ═══════════════════════════════════════════════════════
  //  BOOTSTRAP — Direct DB query + 10km radius filter
  // ═══════════════════════════════════════════════════════
  static Future<void> bootstrap() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint(">>> [BOOT] Starting for user: $userId");

    try {
      // ── 1. Verify rider is approved ───────────────────
      final riderRes = await client
          .from('delivery_riders')
          .select('id, name, phone, status, is_approved, is_online, kyc_status')
          .eq('id', userId)
          .maybeSingle();

      if (riderRes == null) {
        debugPrint("!!! [BOOT] Not a registered rider. Logging out.");
        await logout();
        return;
      }

      if (riderRes['is_approved'] != true) {
        debugPrint("!!! [BOOT] Pending approval.");
        bootstrapData = {
          'rider_name': riderRes['name'] ?? 'Partner',
          'pending_approval': true,
          'orders': [],
          'stats': {'deliveries': 0, 'earnings': 0},
        };
        _instance.notify();
        return;
      }

      final riderName = riderRes['name'] ?? 'Partner';

      // ── 2. Get rider's REAL GPS location ─────────────
      try {
        final pos = await LocationService()
            .getCurrentPosition()
            .timeout(const Duration(seconds: 5));
        _riderLat = pos.latitude;
        _riderLng = pos.longitude;
        debugPrint(">>> [BOOT] Rider GPS: $_riderLat, $_riderLng");
      } catch (e) {
        debugPrint(">>> [BOOT] GPS not available: $e");
        // Keep last known position if available
      }

      // ── 3. Fetch MY active orders (no radius limit) ──
      List<Map<String, dynamic>> myOrders = [];
      try {
        final myRes = await client
            .from('orders')
            .select()
            .eq('rider_id', userId)
            .gte('created_at', DateTime.now().subtract(const Duration(hours: 24)).toIso8601String())
            .not('status', 'in',
                '(DELIVERED,CANCELLED,COMPLETED,delivered,cancelled,completed)');

        myOrders = await enrichOrders(List<Map<String, dynamic>>.from(myRes));
        myOrders = _processOrders(myOrders, null, null);
        debugPrint(">>> [BOOT] My active orders: ${myOrders.length}");
      } catch (e) {
        debugPrint(">>> [BOOT] My orders error: $e");
      }

      // ── 4. Fetch UNASSIGNED orders then filter by 10km ─
      List<Map<String, dynamic>> availableOrders = [];
      try {
        final availRes = await client
            .from('orders')
            .select('''
              id, status, total, delivery_fee, created_at,
              pickup_lat, pickup_lng, delivery_lat, delivery_lng,
              delivery_address, rider_id, vendor_id, customer_id
            ''')
            .isFilter('rider_id', null)
            .gte('created_at', DateTime.now().toIso8601String().substring(0, 10))
            .or('status.eq.PLACED,status.eq.placed,status.eq.ACCEPTED,status.eq.accepted,status.eq.PREPARING,status.eq.preparing,status.eq.READY,status.eq.ready,status.eq.READY_FOR_PICKUP,status.eq.ready_for_pickup,status.eq.CONFIRMED,status.eq.confirmed,status.eq.ADMIN_CONFIRMED,status.eq.admin_confirmed');

        // Process + apply 10km radius filter using REAL GPS
        List<Map<String, dynamic>> enrichedAvail = await enrichOrders(List<Map<String, dynamic>>.from(availRes));
        final processed = _processOrders(enrichedAvail, _riderLat, _riderLng);
        availableOrders = processed;
        debugPrint(
            ">>> [BOOT] Available within 10km: ${availableOrders.length} (from ${availRes.length} total)");
      } catch (e) {
        debugPrint(">>> [BOOT] Available orders error: $e");
      }

      // ── 5. Earnings ───────────────────────────────────
      Map<String, dynamic> stats = {'deliveries': 0, 'earnings': 0.0};
      try {
        final deliveredRes = await client
            .from('orders')
            .select('id, total, delivery_fee')
            .eq('rider_id', userId)
            .or('status.eq.DELIVERED,status.eq.delivered');

        final deliveries = deliveredRes.length;
        final earnings = (deliveredRes as List).fold<double>(
          0.0,
          (sum, o) =>
              sum +
              ((o['delivery_fee'] as num?)?.toDouble() ??
                  (o['total'] as num? ?? 0) * 0.15),
        );
        stats = {'deliveries': deliveries, 'earnings': earnings};
      } catch (e) {
        debugPrint(">>> [BOOT] Stats error: $e");
      }

      bootstrapData = {
        'rider_name': riderName,
        'rider_id': riderRes['id'],
        'rider_lat': _riderLat,
        'rider_lng': _riderLng,
        'orders': [...myOrders, ...availableOrders],
        'stats': stats,
      };

      debugPrint(
          ">>> [BOOT] DONE. My=${myOrders.length} + Near=${availableOrders.length}");

      AppRealtimeHub.activate(userId);
      _instance.notify();
    } catch (e) {
      debugPrint(">>> [BOOT] CRITICAL: $e");
      bootstrapData = {
        'rider_name': 'Partner',
        'orders': [],
        'stats': {'deliveries': 0, 'earnings': 0}
      };
      _instance.notify();
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Process raw orders: flatten joins + apply 10km filter
  // ═══════════════════════════════════════════════════════
  static Future<List<Map<String, dynamic>>> enrichOrders(List<Map<String, dynamic>> orders) async {
    if (orders.isEmpty) return orders;

    try {
      final vendorIds = orders.map((o) => o['vendor_id']?.toString()).where((id) => id != null).toSet().toList();
      final customerIds = orders.map((o) => o['customer_id']?.toString()).where((id) => id != null).toSet().toList();

      final vendorsData = vendorIds.isNotEmpty ? await client.from('vendors').select('id, name, address, latitude, longitude').inFilter('id', vendorIds) : [];
      final customersData = customerIds.isNotEmpty ? await client.from('customer_profiles').select('id, full_name, phone').inFilter('id', customerIds) : [];

      final vendorsMap = {for (var v in vendorsData) v['id'].toString(): v};
      final customersMap = {for (var c in customersData) c['id'].toString(): c};

      for (var o in orders) {
        o['vendors'] = vendorsMap[o['vendor_id']?.toString()];
        o['customer_profiles'] = customersMap[o['customer_id']?.toString()];
      }
    } catch (e) {
      debugPrint(">>> [BOOT] Enrich error: $e");
    }
    return orders;
  }

  static List<Map<String, dynamic>> _processOrders(
      List<Map<String, dynamic>> raw, double? riderLat, double? riderLng) {
    final List<Map<String, dynamic>> result = [];

    for (final o in raw) {
      // Handle both nested join formats
      final vendor = (o['vendors'] as Map<String, dynamic>?) ?? {};
      final customer = (o['customer_profiles'] as Map<String, dynamic>?) ?? {};

      // Get vendor's REAL coordinates
      final vendorLat = _toDouble(vendor['latitude']);
      final vendorLng = _toDouble(vendor['longitude']);

      // Pickup = order's own pickup coords, else fall back to vendor coords
      final pickupLat = _toDouble(o['pickup_lat']) ?? vendorLat;
      final pickupLng = _toDouble(o['pickup_lng']) ?? vendorLng;

      // ── 10km radius filter (only for unassigned, when rider has GPS) ──
      if (riderLat != null && riderLng != null) {
        if (pickupLat == null || pickupLng == null) {
          debugPrint(">>> [FILTER] Skip order ${o['id']}: vendor has no GPS");
          continue;
        }
        final distKm = _haversineKm(riderLat, riderLng, pickupLat, pickupLng);
        if (distKm > _radiusKm) {
          debugPrint(
              ">>> [FILTER] Order ${o['id']}: ${distKm.toStringAsFixed(1)}km — OUTSIDE ${_radiusKm}km (Skipped)");
          continue;
        }
        debugPrint(
            ">>> [FILTER] Order ${o['id']}: ${distKm.toStringAsFixed(1)}km ✅ WITHIN ${_radiusKm}km (Added)");
      } else {
        debugPrint(">>> [FILTER] No Rider GPS: Order ${o['id']} added without radius check");
      }

      result.add({
        ...o,
        'joined_vendor_name': vendor['name'],
        'vendor_address': vendor['address'],
        'resolved_pickup_lat': pickupLat,
        'resolved_pickup_lng': pickupLng,
        'joined_customer_name': customer['full_name'] ?? customer['name'],
        'customer_phone': customer['phone'],
      });
    }

    return result;
  }

  // Haversine distance formula
  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius in km
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _deg2rad(double deg) => deg * pi / 180.0;

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

// ═══════════════════════════════════════════════════════
//  REAL-TIME HUB
// ═══════════════════════════════════════════════════════
class AppRealtimeHub {
  static RealtimeChannel? _channel;

  static void activate(String userId) {
    deactivate();
    debugPrint(">>> [HUB] Activating real-time for: $userId");

    _channel = SupabaseConfig.client
        .channel('rider_hub_v16_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint(">>> [HUB] Order change → re-bootstrapping");
            SupabaseConfig.bootstrap();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'delivery_riders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint(">>> [HUB] Rider profile change → re-bootstrapping");
            SupabaseConfig.bootstrap();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec['user_id'] == userId || rec['user_id'] == 'BROADCAST') {
              NotificationService.showLocalNotification(
                title: rec['title'] ?? 'New Order',
                body: rec['message'] ?? 'A new order is waiting.',
              );
              SupabaseConfig.bootstrap();
            }
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
          ">>> [HUB] Status: $status ${error != null ? '| Error: $error' : ''}");
    });
  }

  static void deactivate() {
    if (_channel != null) {
      SupabaseConfig.client.removeChannel(_channel!);
      _channel = null;
    }
  }
}

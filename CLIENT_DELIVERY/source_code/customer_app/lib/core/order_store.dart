import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'supabase_config.dart';
import 'profile_store.dart';

/// [OrderStore] - HIGH VELOCITY PRODUCTION ENGINE
/// MISSION: Zero-latency order visibility and historical recovery. No indicators, no manual syncs.
class OrderStore extends ChangeNotifier {
  static final OrderStore _instance = OrderStore._internal();
  factory OrderStore() => _instance;
  OrderStore._internal();

  final List<Map<String, dynamic>> orders = [];
  bool hasLoaded = false;
  bool isSearching = false; // Kept for manual sync only

  /// 🏎️ INSTANT BOOT: Pull from local disk immediately
  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('cached_orders');
      if (data != null) {
        final List decoded = jsonDecode(data);
        orders.clear();
        orders.addAll(List<Map<String, dynamic>>.from(decoded));
        hasLoaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Disk load failed: $e");
    }
    // SILENT BACKGROUND FETCH: No UI blocking
    fetchOrders(silent: true);
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_orders', jsonEncode(orders));
    } catch (e) {
      debugPrint("Disk save failed: $e");
    }
  }

  /// 🚀 HYPER-SPEED FETCH: Recovers all historical data silently.
  Future<void> fetchOrders({bool silent = false}) async {
    String? uid = SupabaseConfig.forcedUserId ?? SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;

    if (!silent) {
        isSearching = true;
        notifyListeners();
    }

    try {
      final List<String> searchIds = [uid];
      final p = ProfileStore().profile;
      String? profilePhone = p?['phone']?.toString();
      
      if (profilePhone == null && uid.startsWith('sms_auth_')) {
          profilePhone = uid.replaceFirst('sms_auth_', '');
      }

      String? shortPhone;
      if (profilePhone != null) {
          final digits = profilePhone.replaceAll(RegExp(r'\D'), '');
          shortPhone = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
          if (!searchIds.contains(shortPhone)) searchIds.add(shortPhone);
          if (!searchIds.contains('sms_auth_$shortPhone')) searchIds.add('sms_auth_$shortPhone');
      }

      debugPrint('>>> [ORDERS] Fetching for IDs: $searchIds');

      var query = SupabaseConfig.client.from('order_tracking_stabilized_v1').select();
      query = query.inFilter('customer_id', searchIds);

      final res = await query.order('created_at', ascending: false).limit(200);
      final List<Map<String, dynamic>> rawList = List<Map<String, dynamic>>.from(res);
      
      // 🛡️ STRICT FILTERING: Ensure we only keep what matches our known IDs
      final List<Map<String, dynamic>> filtered = rawList.where((o) {
          final cid = o['customer_id']?.toString();
          final dphone = o['delivery_phone']?.toString().replaceAll(RegExp(r'\D'), '');
          final dshort = (dphone != null && dphone.length >= 10) ? dphone.substring(dphone.length - 10) : dphone;
          
          // Privacy filter: Ensure orders really belong to the current search IDs
          return searchIds.contains(cid);
      }).toList();

      final normalizedMatches = filtered.map((o) => _normalizeOrder(o)).whereType<Map<String, dynamic>>().toList();

      // 🛡️ DEDUPLICATION: Use a Map to keep only unique IDs
      final Map<String, Map<String, dynamic>> uniqueMap = {};
      for (var o in normalizedMatches) {
          final id = (o['order_id'] ?? o['id']).toString();
          if (!uniqueMap.containsKey(id)) {
              uniqueMap[id] = o;
          }
      }

      orders.clear();
      orders.addAll(uniqueMap.values.toList());
      orders.sort((a, b) => (b['created_at'] ?? '').toString().compareTo((a['created_at'] ?? '').toString()));

      _saveToDisk();
      hasLoaded = true;
    } catch (e) {
      debugPrint("Silent History Sync stalled: $e");
    } finally {
      isSearching = false;
      hasLoaded = true;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _normalizeOrder(Map<String, dynamic> o) {
      final copy = Map<String, dynamic>.from(o);
      final status = (copy['order_status'] ?? copy['status'] ?? copy['payment_status'] ?? 'PLACED').toString().toUpperCase();
      final method = (copy['payment_method'] ?? 'UPI').toString().toUpperCase();
      
      // 🛡️ DO NOT hide old pending/failed orders, users want to see their full history.
      if ((status == 'PENDING' || status == 'PAYMENT_PENDING' || status == 'PAYMENT_FAILED' || status == 'UPI_PENDING') && method != 'COD') {
          copy['status'] = 'PAYMENT PENDING';
      } else if (status == 'SUCCESS' || status == 'PAID') {
          copy['status'] = 'PLACED';
      } else if (status == 'CANCELLED' || status == 'CANCELED') {
          copy['status'] = 'CANCELLED';
      } else {
          copy['status'] = status;
      }
      
      copy['order_status'] = status;
      
      final t = (copy['total_amount'] ?? copy['total'] ?? 0);
      copy['total'] = t;
      copy['total_amount'] = t;

      if (copy['vendor_name'] == null) {
         copy['vendor_name'] = copy['vendors']?['name'] ?? copy['vendor_display_name'] ?? 'Restaurant';
      }
      return copy;
  }

  /// ⚡ INSTANT HYDRATION: Called immediately on real-time event.
  /// Fetches from the stabilized view for a specific ID in parallel with local merge.
  Future<void> hydrateOrderSync(String orderId) async {
      try {
          final res = await SupabaseConfig.client
              .from('order_tracking_stabilized_v1')
              .select()
              .eq('id', orderId)
              .maybeSingle();
              
          if (res != null) {
              final normalized = _normalizeOrder(Map<String, dynamic>.from(res));
              if (normalized != null) {
                  final idx = orders.indexWhere((o) => (o['order_id'] ?? o['id']).toString() == orderId);
                  if (idx != -1) {
                      orders[idx] = normalized;
                  } else {
                      orders.insert(0, normalized);
                  }
                  notifyListeners();
                  _saveToDisk();
              }
          }
      } catch (_) {}
  }

  void updateFromRealtime(Map<String, dynamic> record) {
    final id = (record['id'] ?? record['order_id']).toString();
    if (record.isEmpty) return;

    String? uid = SupabaseConfig.forcedUserId ?? SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;

    final p = ProfileStore().profile;
    final String? myPhone = p?['phone']?.toString().replaceAll(RegExp(r'\D'), '');
    final String? orderPhone = record['delivery_phone']?.toString().replaceAll(RegExp(r'\D'), '');

    // Robust Phone Matching (Last 10 digits)
    final mShort = (myPhone != null && myPhone.length >= 10) ? myPhone.substring(myPhone.length - 10) : myPhone;
    final oShort = (orderPhone != null && orderPhone.length >= 10) ? orderPhone.substring(orderPhone.length - 10) : orderPhone;

    bool isMine = record['customer_id']?.toString() == uid || 
                  record['customer_id']?.toString() == 'sms_auth_$mShort';

    if (isMine) {
      debugPrint(">>> [ORDER STORE] Accepting Realtime Update for Order: ${record['id']}");
      
      // Deduplicate before inserting
      final id = (record['order_id'] ?? record['id']).toString();
      final index = orders.indexWhere((o) => (o['order_id'] ?? o['id']).toString() == id);
      
      final normalized = _normalizeOrder(record);
      if (normalized != null) {
          if (index != -1) {
              orders[index] = normalized;
          } else {
              orders.insert(0, normalized);
          }
          notifyListeners();
      } else if (index != -1) {
          // If it became null (stale pending), remove it
          orders.removeAt(index);
          notifyListeners();
      }
    } else {
      debugPrint(">>> [SECURITY] Blocked unauthorized realtime order update for ID: ${record['id']}");
    }
  }

  void updateLiveLocation(Map<String, dynamic>? record) {
    if (record == null || record['order_id'] == null) return;
    final orderId = record['order_id'].toString().toLowerCase();
    final index = orders.indexWhere((o) => (o['order_id'] ?? o['id']).toString().toLowerCase() == orderId);

    if (index != -1) {
      orders[index]['rider_live_lat'] = record['rider_lat'];
      orders[index]['rider_live_lng'] = record['rider_lng'];
      notifyListeners();
    }
  }

  void clear() {
    orders.clear();
    notifyListeners();
  }
}

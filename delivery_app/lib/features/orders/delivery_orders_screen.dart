import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/pro_theme.dart';
import '../../core/supabase_config.dart';
import '../../core/services/location_service.dart';
import 'order_chat_screen.dart';
import '../../core/services/maps_launcher.dart';

class DeliveryOrdersScreen extends StatefulWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  State<DeliveryOrdersScreen> createState() => _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen> {
  Map<String, dynamic>? _activeOrder;
  List<Map<String, dynamic>> _availableOrders = [];
  bool _loading = true;
  bool _actionInProgress = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) {
      SupabaseConfig.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  // ── Haversine distance in km ────────────────────────────────────────────────
  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  // ── FETCH ORDERS — Use the RPC (proven working server-side) with live GPS ──
  Future<void> _fetchOrders() async {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    if (mounted) setState(() => _loading = true);

    try {
      // Step 1: Get live GPS (timeout 5s, fallback to null = show all orders)
      double? riderLat;
      double? riderLng;
      try {
        final pos = await LocationService()
            .getCurrentPosition()
            .timeout(const Duration(seconds: 5));
        riderLat = pos.latitude;
        riderLng = pos.longitude;
        SupabaseConfig.bootstrapData ??= {};
        SupabaseConfig.bootstrapData!['rider_lat'] = riderLat;
        SupabaseConfig.bootstrapData!['rider_lng'] = riderLng;
        debugPrint('>>> [DISPATCH] GPS: $riderLat, $riderLng');
      } catch (e) {
        debugPrint('>>> [DISPATCH] GPS unavailable: $e (will show all orders)');
        riderLat = SupabaseConfig.bootstrapData?['rider_lat'] as double?;
        riderLng = SupabaseConfig.bootstrapData?['rider_lng'] as double?;
      }

      // Step 2: Call the RPC — PROVEN to work server-side
      final response = await SupabaseConfig.client.rpc(
        'get_rider_dashboard_v2',
        params: {
          'p_rider_auth_id': userId,
          'p_lat': riderLat,
          'p_lng': riderLng,
        },
      );

      final Map<String, dynamic> data =
          response is Map ? Map<String, dynamic>.from(response) : {};

      final activeOrders =
          List<Map<String, dynamic>>.from(data['active_orders'] ?? []);
      final availableOrders =
          List<Map<String, dynamic>>.from(data['available_orders'] ?? []);

      debugPrint(
          '>>> [DISPATCH] RPC returned: active=${activeOrders.length} available=${availableOrders.length}');

      // Step 3: Start tracking if I have an active order
      Map<String, dynamic>? active;
      if (activeOrders.isNotEmpty) {
        active = activeOrders.first;
        LocationService()
            .startTracking(userId, orderId: active['id'].toString());
      }

      if (mounted) {
        setState(() {
          _activeOrder = active;
          _availableOrders = availableOrders;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('>>> [DISPATCH] Error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }


  String _getEffectiveStatus(Map<String, dynamic> o) {
    final s = o['status']?.toString().toUpperCase() ?? '';
    final os = o['order_status']?.toString().toUpperCase() ?? '';
    // Priority 1: Final states (if either says delivered, it's delivered)
    if (['DELIVERED', 'COMPLETED', 'CANCELLED', 'REJECTED'].contains(os)) return os;
    if (['DELIVERED', 'COMPLETED', 'CANCELLED', 'REJECTED'].contains(s)) return s;
    // Priority 2: Pickup states
    if (['PICKED_UP', 'RIDER_PICKED_UP', 'OUT_FOR_DELIVERY'].contains(os)) return 'PICKED_UP';
    if (['PICKED_UP', 'RIDER_PICKED_UP', 'OUT_FOR_DELIVERY'].contains(s)) return 'PICKED_UP';
    // Priority 3: Prep states
    if (os.isNotEmpty && os != 'PLACED') return os;
    return s.isNotEmpty ? s : 'PLACED';
  }

  // Flatten join data into a flat map ─────────────────────────────────────────
  Map<String, dynamic> _flattenOrder(Map<String, dynamic> raw) {
    final vendor = (raw['vendors'] as Map<String, dynamic>?) ?? {};
    final customer = (raw['customer_profiles'] as Map<String, dynamic>?) ?? {};

    final vendorLat = _toDouble(vendor['latitude']);
    final vendorLng = _toDouble(vendor['longitude']);
    final pickupLat = _toDouble(raw['pickup_lat']) ?? vendorLat;
    final pickupLng = _toDouble(raw['pickup_lng']) ?? vendorLng;

    return {
      ...raw,
      'joined_vendor_name': vendor['name'] ?? 'Restaurant',
      'vendor_address': vendor['address'] ?? 'Pickup Location',
      'resolved_pickup_lat': pickupLat,
      'resolved_pickup_lng': pickupLng,
      'joined_customer_name': customer['full_name'] ?? 'Customer',
      'customer_phone': customer['phone'],
    };
  }

  void _subscribeRealtime() {
    final userId = SupabaseConfig.client.auth.currentUser?.id;
    if (userId == null) return;

    _channel = SupabaseConfig.client
        .channel('dispatch_v20_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('>>> [DISPATCH] Real-time order update → refreshing');
            _fetchOrders();
          })
        .subscribe((status, [error]) {
      debugPrint('>>> [DISPATCH] Channel: $status');
    });
  }

  Future<void> _acceptMission(String orderId) async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;

      final res = await SupabaseConfig.client.rpc('accept_order_v1', params: {
        'p_order_id': orderId,
        'p_rider_id': user.id,
      });

      final Map<String, dynamic> data = Map<String, dynamic>.from(res);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Acceptance failed');
      }

      LocationService().startTracking(user.id, orderId: orderId);
      await _fetchOrders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('MISSION ACCEPTED: PROCEED TO RESTAURANT'),
              backgroundColor: ProTheme.secondary),
        );
      }
    } catch (e) {
      debugPrint('Accept Mission Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _pickUpFood() async {
    if (_actionInProgress) return;
    setState(() => _actionInProgress = true);
    try {
      final orderId = _activeOrder!['id'];
      await SupabaseConfig.client.rpc('rider_pickup_order_v2', params: {
        'p_order_id': orderId,
      });

      await _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('FOOD PICKED UP: NAVIGATING TO CUSTOMER'),
              backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Pickup Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  // ── CONFIRM DELIVERY — Checks status first to avoid double-delivery error ──
  Future<void> _onDeliveryComplete() async {
    if (_actionInProgress) return;

    final orderId = _activeOrder!['id'];
    final currentStatus = _getEffectiveStatus(_activeOrder!);

    // Guard: already delivered → just refresh and clear
    if (['DELIVERED', 'COMPLETED', 'CANCELLED'].contains(currentStatus)) {
      LocationService().stopTracking();
      await _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Order already marked as delivered.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    setState(() => _actionInProgress = true);

    try {
      // Re-read current status from DB before calling RPC
      final fresh = await SupabaseConfig.client
          .from('orders')
          .select('status')
          .eq('id', orderId)
          .maybeSingle();

      final freshStatus = _getEffectiveStatus(fresh ?? {});
      if (['DELIVERED', 'COMPLETED', 'CANCELLED'].contains(freshStatus)) {
        LocationService().stopTracking();
        await _fetchOrders();
        if (mounted) {
          setState(() => _actionInProgress = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Order already delivered!'),
                backgroundColor: Colors.green),
          );
        }
        return;
      }

      await SupabaseConfig.client.rpc('rider_deliver_order_v3', params: {
        'p_order_id': orderId,
      });

      LocationService().stopTracking(); // ADDED TO STOP GPS PULSE

      final total = (_activeOrder!['total_amount'] as num?) ?? (_activeOrder!['total'] as num?) ?? 0;
      final earnings = (_activeOrder!['delivery_fee'] as num?) ?? (total * 0.10);

      await SupabaseConfig.bootstrap();

      if (mounted) {
        _showDeliverySummary(total, earnings);
      }
    } catch (e) {
      debugPrint('Delivery Completion Error: $e');
      // If it's a "final state" error, the order IS delivered — treat as success
      if (e.toString().contains('final state') ||
          e.toString().contains('DELIVERED')) {
        LocationService().stopTracking();
        await _fetchOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('✅ Delivery confirmed!'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  Future<void> _callCustomer() async {
    final phone = _activeOrder?['customer_phone']?.toString() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available')),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _availableOrders.isEmpty && _activeOrder == null) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)));
    }

    if (_activeOrder != null) {
      return _buildActiveOrderView();
    }

    if (_availableOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchOrders,
        backgroundColor: ProTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.7,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.radar,
                        size: 64, color: ProTheme.primary.withOpacity(0.3))
                    .animate(onPlay: (c) => c.repeat())
                    .rotate(duration: 2.seconds)
                    .shimmer(),
                const SizedBox(height: 24),
                Text('NO MISSIONS NEARBY',
                    style: ProTheme.header
                        .copyWith(fontSize: 16, color: Colors.white)),
                Text('Pull down to scan for deployments',
                    style:
                        ProTheme.body.copyWith(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Showing nearby active missions',
                    style: ProTheme.body
                        .copyWith(fontSize: 10, color: Colors.white30)),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      backgroundColor: ProTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 250),
        itemCount: _availableOrders.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _buildListHeader(_availableOrders.length);
          return _buildMissionCard(_availableOrders[index - 1]);
        },
      ),
    );
  }

  Widget _buildListHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          const Icon(LucideIcons.zap, color: ProTheme.primary, size: 16),
          const SizedBox(width: 8),
          Text('AVAILABLE MISSIONS', style: ProTheme.label.copyWith(fontSize: 11)),
          const Spacer(),
          Text('$count TODAY',
              style: ProTheme.label.copyWith(fontSize: 10, color: ProTheme.gray)),
        ],
      ).animate().fadeIn(),
    );
  }

  // ── ACTIVE ORDER VIEW ───────────────────────────────────────────────────────
  Widget _buildActiveOrderView() {
    final o = _activeOrder!;
    final rawStatus = (o['order_status'] ?? o['status'] ?? '').toString().toUpperCase();

    final isAtPickup = !['RIDER_PICKED_UP', 'OUT_FOR_DELIVERY', 'PICKED_UP'].contains(rawStatus);

    // Support both flat fields and nested join format
    final vendor = (o['vendors'] as Map<String, dynamic>?) ?? {};
    final customer = (o['customer_profiles'] as Map<String, dynamic>?) ?? {};

    final vName = o['vendor_name'] ?? vendor['name'] ?? 'Restaurant';
    final vAddr = o['vendor_address'] ?? vendor['address'] ?? 'Pickup Location';
    final cName = o['customer_name'] ?? customer['full_name'] ?? o['joined_customer_name'] ?? 'Customer';
    final cAddr = o['delivery_address'] ?? 'Delivery Location';

    final vLat = _toDouble(o['resolved_pickup_lat']) ?? _toDouble(o['vendor_lat']) ?? _toDouble(vendor['latitude']) ?? 0.0;
    final vLng = _toDouble(o['resolved_pickup_lng']) ?? _toDouble(o['vendor_lng']) ?? _toDouble(vendor['longitude']) ?? 0.0;
    final cLat = _toDouble(o['delivery_lat']) ?? 0.0;
    final cLng = _toDouble(o['delivery_lng']) ?? 0.0;

    // Distance to current target
    final riderLat = SupabaseConfig.bootstrapData?['rider_lat'] as double?;
    final riderLng = SupabaseConfig.bootstrapData?['rider_lng'] as double?;
    double? distToTarget;
    if (riderLat != null && riderLng != null) {
      final tLat = isAtPickup ? vLat : cLat;
      final tLng = isAtPickup ? vLng : cLng;
      if (tLat != 0.0 && tLng != 0.0) {
        distToTarget = _haversineKm(riderLat, riderLng, tLat, tLng);
      }
    }

    final statusDisplay =
        _activeOrder!['status_display'] ?? 'MISSION IN PROGRESS';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 250),
      child: Column(
        children: [
          // ── STATUS BAR ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: ProTheme.slate,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ProTheme.primary.withOpacity(0.2))),
            child: Row(
              children: [
                const Icon(LucideIcons.activity,
                    color: ProTheme.primary, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(statusDisplay.toString().toUpperCase(),
                      style: ProTheme.label.copyWith(
                          color: ProTheme.primary,
                          fontSize: 10,
                          letterSpacing: 1.5)),
                ),
                if (distToTarget != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ProTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${distToTarget.toStringAsFixed(1)} km away',
                      style: ProTheme.label.copyWith(
                          color: ProTheme.primary, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ).animate().fadeIn().slideX(begin: -0.2, end: 0),

          const SizedBox(height: 24),

          // ── TARGET CARD ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: ProTheme.cardDecor.copyWith(color: ProTheme.slate),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                          color: ProTheme.primary, shape: BoxShape.circle),
                      child: Icon(
                          isAtPickup ? LucideIcons.store : LucideIcons.home,
                          color: ProTheme.slate),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              isAtPickup
                                  ? 'TARGET: RESTAURANT'
                                  : 'TARGET: CUSTOMER',
                              style: ProTheme.label
                                  .copyWith(color: ProTheme.primary, fontSize: 9)),
                          Text(
                              isAtPickup ? vName : cName,
                              style: ProTheme.title
                                  .copyWith(color: Colors.white, fontSize: 18)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 32),

                // Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.mapPin,
                        color: ProTheme.gray, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(isAtPickup ? vAddr : cAddr,
                            style: ProTheme.body.copyWith(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 13))),
                  ],
                ),

                const SizedBox(height: 32),

                // ── ACTION BUTTON ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _actionInProgress
                        ? null
                        : (isAtPickup ? _pickUpFood : _onDeliveryComplete),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ProTheme.secondary,
                      disabledBackgroundColor:
                          ProTheme.secondary.withOpacity(0.4),
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                      shadowColor: ProTheme.secondary.withOpacity(0.3),
                    ),
                    child: _actionInProgress
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                  isAtPickup
                                      ? LucideIcons.checkCircle
                                      : LucideIcons.packageCheck,
                                  color: Colors.white,
                                  size: 20),
                              const SizedBox(width: 12),
                              Text(
                                  isAtPickup
                                      ? 'CONFIRM PICKUP'
                                      : 'CONFIRM DELIVERY',
                                  style: ProTheme.button.copyWith(
                                      color: Colors.white, fontSize: 16)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── NAVIGATION ──────────────────────────────────────────────────────
          _buildNavigationBlock(vLat, vLng, cLat, cLng, isAtPickup),

          // ── ORDER MANIFEST ──────────────────────────────────────────────────
          _buildOrderDetailsBlock(),

          const SizedBox(height: 12),

          // ── CALL + CHAT (only in delivery phase) ────────────────────────────
            _actionBtn(LucideIcons.phone, 'CALL CUSTOMER: ${cName.toUpperCase()}', _callCustomer),
            const SizedBox(height: 12),
            _actionBtn(LucideIcons.messageSquare, 'SECURE CHAT: $cName', () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => OrderChatScreen(
                          orderId: _activeOrder!['id'].toString(),
                          customerName: cName)));
            }, isPrimary: true),
        ],
      ),
    );
  }

  Widget _buildNavigationBlock(
      double vLat, double vLng, double cLat, double cLng, bool isAtPickup) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration:
          ProTheme.cardDecor.copyWith(color: Colors.white.withOpacity(0.03)),
      child: ListTile(
        onTap: () {
          final lat = isAtPickup ? vLat : cLat;
          final lng = isAtPickup ? vLng : cLng;
          if (lat != 0) MapsLauncher.launchNavigation(lat, lng);
        },
        leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: ProTheme.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(LucideIcons.navigation,
                color: ProTheme.primary, size: 18)),
        title: Text('OPEN TACTICAL NAVIGATION',
            style: ProTheme.label.copyWith(fontSize: 10, color: Colors.white)),
        subtitle: Text('Google Maps Road Routing',
            style: ProTheme.body.copyWith(fontSize: 11, color: Colors.grey)),
        trailing:
            const Icon(LucideIcons.chevronRight, color: Colors.grey, size: 16),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
      {bool isPrimary = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary
              ? ProTheme.primary.withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          foregroundColor: isPrimary ? ProTheme.primary : Colors.white70,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: isPrimary
              ? const BorderSide(color: ProTheme.primary)
              : BorderSide.none,
        ),
      ),
    );
  }

  // ── AVAILABLE ORDER CARD ────────────────────────────────────────────────────
  Widget _buildMissionCard(Map<String, dynamic> order) {
    final vName = order['vendor_name'] ?? 'Restaurant';
    final vAddr = order['vendor_address'] ?? 'Pickup Location';
    final total = (order['total_amount'] as num?) ?? (order['total'] as num?) ?? 0;
    final earnings = (order['delivery_fee'] as num?) ?? (total * 0.10); 
    final dist = _toDouble(order['distance_km']);
    final payMethod =
        order['payment_method']?.toString().toUpperCase() ?? 'COD';

    // Format date
    String dateStr = '';
    if (order['created_at'] != null) {
      try {
        final d = DateTime.parse(order['created_at'].toString()).toLocal();
        dateStr =
            '${d.day}/${d.month}/${d.year} ${_fmt12(d.hour)}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
      } catch (_) {}
    }

    // Item summary
    final items = order['items'] as List<dynamic>? ?? [];
    final itemSummary = items.isEmpty
        ? 'No items'
        : items
            .map((i) => '${i['qty'] ?? 1}x ${i['name'] ?? ''}')
            .join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: ProTheme.cardDecor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('NEW ORDER', style: ProTheme.label.copyWith(fontSize: 9)),
              if (dist != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ProTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${dist.toStringAsFixed(1)} km away',
                      style: ProTheme.label
                          .copyWith(fontSize: 9, color: ProTheme.primary)),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: payMethod == 'COD'
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(payMethod,
                    style: ProTheme.label.copyWith(
                        fontSize: 9,
                        color: payMethod == 'COD'
                            ? Colors.orange
                            : Colors.green)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Restaurant name + address
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vName, style: ProTheme.title),
                    Text(vAddr,
                        style:
                            ProTheme.body.copyWith(fontSize: 12, color: ProTheme.gray),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('₹${earnings.toInt()}',
                      style: ProTheme.header
                          .copyWith(fontSize: 22, color: ProTheme.secondary)),
                  Text('Earnings', style: ProTheme.label.copyWith(fontSize: 8, color: ProTheme.secondary.withOpacity(0.7))),
                ],
              ),
            ],
          ),

          // Item summary
          if (itemSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(itemSummary,
                style: ProTheme.body.copyWith(
                    fontSize: 11, color: Colors.white54),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],

          // Date
          if (dateStr.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(dateStr,
                style: ProTheme.body.copyWith(
                    fontSize: 10, color: Colors.white30)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _actionInProgress
                  ? null
                  : () => _acceptMission(order['id'].toString()),
              style: ProTheme.ctaButton,
              child: _actionInProgress
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2))
                  : const Text('ACCEPT DEPLOYMENT'),
            ),
          )
        ],
      ),
    );
  }

  // ── ORDER MANIFEST (active order details) ───────────────────────────────────
  Widget _buildOrderDetailsBlock() {
    final order = _activeOrder!;
    final itemsRaw = order['items'] as List<dynamic>? ?? [];
    final List<Widget> itemWidgets = itemsRaw.map<Widget>((item) {
      final name = item['name'] ?? 'Item';
      final qty = item['qty'] ?? 1;
      final price = item['price'] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${qty}x $name',
                style:
                    ProTheme.body.copyWith(color: Colors.white, fontSize: 12)),
            Text('₹$price',
                style:
                    ProTheme.body.copyWith(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }).toList();

    if (itemWidgets.isEmpty) {
      itemWidgets.add(Text('Details not available.',
          style: ProTheme.body.copyWith(color: Colors.white54, fontSize: 12)));
    }

    // Use toLocal() to show correct device-timezone date
    String formattedDate = 'N/A';
    if (order['created_at'] != null) {
      try {
        final d = DateTime.parse(order['created_at'].toString()).toLocal();
        final h = _fmt12(d.hour);
        final m = d.minute.toString().padLeft(2, '0');
        final ampm = d.hour >= 12 ? 'PM' : 'AM';
        formattedDate = '${d.day}/${d.month}/${d.year} $h:$m $ampm';
      } catch (_) {}
    }

    final paymentMethod =
        order['payment_method']?.toString().toUpperCase() ?? 'COD';
    final total = (order['total_amount'] as num?) ?? (order['total'] as num?) ?? 0;
    final deliveryFee = (order['delivery_fee'] as num?) ?? (total * 0.10); // 10% fallback

    // Distance to current target
    final status = order['status']?.toString().toUpperCase() ?? '';
    final isAtPickup =
        !['RIDER_PICKED_UP', 'OUT_FOR_DELIVERY', 'PICKED_UP'].contains(status);
    final riderLat = SupabaseConfig.bootstrapData?['rider_lat'] as double?;
    final riderLng = SupabaseConfig.bootstrapData?['rider_lng'] as double?;
    final vLat = _toDouble(order['resolved_pickup_lat']) ?? 0.0;
    final vLng = _toDouble(order['resolved_pickup_lng']) ?? 0.0;
    final cLat = _toDouble(order['delivery_lat']) ?? 0.0;
    final cLng = _toDouble(order['delivery_lng']) ?? 0.0;

    double? dist;
    if (riderLat != null && riderLng != null) {
      final tLat = isAtPickup ? vLat : cLat;
      final tLng = isAtPickup ? vLng : cLng;
      if (tLat != 0.0 && tLng != 0.0) {
        dist = _haversineKm(riderLat, riderLng, tLat, tLng);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24, top: 4),
      decoration: ProTheme.cardDecor.copyWith(color: ProTheme.slate),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ORDER MANIFEST',
                  style: ProTheme.label
                      .copyWith(color: ProTheme.primary, fontSize: 10)),
              if (dist != null)
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin,
                        color: ProTheme.primary, size: 12),
                    const SizedBox(width: 4),
                    Text('${dist.toStringAsFixed(1)} km',
                        style: ProTheme.label.copyWith(
                            color: ProTheme.primary, fontSize: 10)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(formattedDate,
              style: ProTheme.body.copyWith(color: Colors.white54, fontSize: 11)),
          const Divider(color: Colors.white10, height: 24),
          ...itemWidgets,
          const Divider(color: Colors.white10, height: 24),
          // Payment method
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PAYMENT METHOD',
                  style: ProTheme.label.copyWith(fontSize: 10)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: paymentMethod == 'COD'
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(paymentMethod,
                    style: ProTheme.label.copyWith(
                        color: paymentMethod == 'COD'
                            ? Colors.orange
                            : Colors.green,
                        fontSize: 10)),
              )
            ],
          ),
          const SizedBox(height: 12),
          // Collect cash / order total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  paymentMethod == 'COD' ? 'COLLECT CASH' : 'ORDER TOTAL',
                  style: ProTheme.label.copyWith(fontSize: 10)),
              Text('₹${total.toInt()}',
                  style:
                      ProTheme.title.copyWith(color: Colors.white, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          // Earnings
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('YOUR EARNINGS',
                  style: ProTheme.label
                      .copyWith(color: ProTheme.secondary, fontSize: 10)),
              Text('₹${deliveryFee.toInt()}',
                  style: ProTheme.title
                      .copyWith(color: ProTheme.secondary, fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeliverySummary(num total, num earnings) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: ProTheme.slate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('MISSION ACCOMPLISHED',
            style: TextStyle(color: ProTheme.secondary, fontSize: 18, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.green, size: 64),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Order Total:', style: TextStyle(color: Colors.white70)),
                Text('₹${total.toInt()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Your Earnings:', style: TextStyle(color: ProTheme.secondary)),
                Text('₹${earnings.toInt()}', style: const TextStyle(color: ProTheme.secondary, fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _fetchOrders();
              },
              style: ProTheme.ctaButton,
              child: const Text('READY FOR NEXT MISSION'),
            ),
          ),
        ],
      ),
    );
  }

  int _fmt12(int hour) {
    if (hour == 0) return 12;
    if (hour > 12) return hour - 12;
    return hour;
  }
}

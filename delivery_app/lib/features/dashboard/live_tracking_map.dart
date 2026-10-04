import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:http/http.dart' as http;
import '../../core/pro_theme.dart';
import '../../core/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';

// Default location: Krishnan Kovil, Tamil Nadu (User's location)
const _defaultLat = 9.48;
const _defaultLng = 77.78;

class LiveTrackingMap extends StatefulWidget {
  final bool isOnline;
  const LiveTrackingMap({super.key, required this.isOnline});

  @override
  State<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends State<LiveTrackingMap> {
  final MapController _mapController = MapController();
  LatLng _currentPos = const LatLng(_defaultLat, _defaultLng);
  double _heading = 0;
  bool _isSimulating = false;
  bool _gpsReady = false;

  // Only the rider's OWN active order (if any)
  Map<String, dynamic>? _myActiveOrder;
  List<LatLng> _routePoints = [];
  StreamSubscription? _orderSyncSub;
  StreamSubscription<Position>? _positionSub;
  RealtimeChannel? _missionChannel;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _fetchMyActiveOrder();
    _subscribeToMissionUpdates();
  }

  @override
  void dispose() {
    _orderSyncSub?.cancel();
    _positionSub?.cancel();
    if (_missionChannel != null) {
      SupabaseConfig.client.removeChannel(_missionChannel!);
    }
    super.dispose();
  }

  void _subscribeToMissionUpdates() {
    _missionChannel = SupabaseConfig.client
        .channel('mission_radar_v20')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              debugPrint('>>> [MAP] Order update detected. Refreshing...');
              _fetchMyActiveOrder();
            })
        .subscribe((status, [error]) {
      debugPrint('>>> [MAP CHANNEL] Status: $status, Error: $error');
    });
  }

  Future<void> _fetchMyActiveOrder() async {
    final riderId = SupabaseConfig.client.auth.currentUser?.id;
    if (riderId == null) return;

    try {
      final dynamic res = await SupabaseConfig.client
          .rpc('get_active_mission_v1', params: {'p_rider_id': riderId});

      if (res != null && mounted) {
        final mission = Map<String, dynamic>.from(res);
        final vLat = _safeDouble(mission['vendor_lat']);
        final vLng = _safeDouble(mission['vendor_lng']);
        
        setState(() {
          _myActiveOrder = {
            ...mission,
            'joined_vendor_name': mission['vendor_name'] ?? 'Restaurant',
            'joined_customer_name': mission['customer_name'] ?? 'Customer',
            'resolved_pickup_lat': _safeDouble(mission['pickup_lat']) ?? vLat,
            'resolved_pickup_lng': _safeDouble(mission['pickup_lng']) ?? vLng,
          };
        });
        _calculateRoute();
      } else if (mounted) {
        setState(() {
          _myActiveOrder = null;
          _routePoints = [];
        });
      }
    } catch (e) {
      debugPrint('>>> [MAP] Fetch error: $e');
    }
  }

  Future<void> _calculateRoute() async {
    if (_myActiveOrder == null) {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    final status =
        _myActiveOrder!['status']?.toString().toUpperCase() ?? '';

    final isPickupPhase =
        !['RIDER_PICKED_UP', 'OUT_FOR_DELIVERY', 'PICKED_UP'].contains(status);

    LatLng? target;
    if (isPickupPhase) {
      final tLat = _safeDouble(_myActiveOrder!['resolved_pickup_lat']);
      final tLng = _safeDouble(_myActiveOrder!['resolved_pickup_lng']);
      if (tLat != null && tLng != null) target = LatLng(tLat, tLng);
    } else {
      final tLat = _safeDouble(_myActiveOrder!['delivery_lat']);
      final tLng = _safeDouble(_myActiveOrder!['delivery_lng']);
      if (tLat != null && tLng != null) target = LatLng(tLat, tLng);
    }

    if (target == null) return;

    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/${_currentPos.longitude},${_currentPos.latitude};${target.longitude},${target.latitude}?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final List<dynamic> coordinates =
              data['routes'][0]['geometry']['coordinates'];
          setState(() {
            _routePoints = coordinates
                .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('>>> [MAP] Route calculation failed: $e');
      if (mounted) {
        setState(() {
          _routePoints = [_currentPos, target!];
        });
      }
    }
  }

  double? _safeDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPos = LatLng(pos.latitude, pos.longitude);
          _gpsReady = true;
        });
      }
    } catch (e) {
      debugPrint('>>> [GPS] Initial position failed: $e. Using default.');
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _currentPos = LatLng(pos.latitude, pos.longitude);
          _heading = pos.heading;
          _gpsReady = true;
        });
        _broadcastToCloud(pos);
      }
    }, onError: (e) {
      debugPrint('>>> [GPS] Stream error: $e');
    });
  }

  Future<void> _broadcastToCloud(Position pos) async {
    if (!widget.isOnline) return;
    final riderId = SupabaseConfig.client.auth.currentUser?.id;
    if (riderId == null) return;

    try {
      await SupabaseConfig.client.rpc('update_rider_location_v43', params: {
        'p_order_id': _myActiveOrder?['id'],
        'p_rider_id': riderId,
        'p_lat': pos.latitude,
        'p_lng': pos.longitude,
        'p_speed': pos.speed,
        'p_heading': pos.heading,
      });
    } catch (e) {
      debugPrint('>>> [GPS] Broadcast Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveOrder = _myActiveOrder != null;
    final status =
        _myActiveOrder?['status']?.toString().toUpperCase() ?? '';
    final isPickupPhase =
        !['RIDER_PICKED_UP', 'OUT_FOR_DELIVERY', 'PICKED_UP'].contains(status);

    Marker? targetMarker;
    if (hasActiveOrder) {
      double? tLat;
      double? tLng;
      IconData tIcon;

      if (isPickupPhase) {
        tLat = _safeDouble(_myActiveOrder!['resolved_pickup_lat']);
        tLng = _safeDouble(_myActiveOrder!['resolved_pickup_lng']);
        tIcon = LucideIcons.store;
      } else {
        tLat = _safeDouble(_myActiveOrder!['delivery_lat']);
        tLng = _safeDouble(_myActiveOrder!['delivery_lng']);
        tIcon = LucideIcons.home;
      }

      if (tLat != null && tLng != null && tLat != 0.0 && tLng != 0.0) {
        targetMarker = Marker(
          point: LatLng(tLat, tLng),
          width: 50,
          height: 50,
          child: _buildTacticalMarker(tIcon, ProTheme.accent, true),
        );
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPos,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: ProTheme.primary,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPos,
                    width: 70,
                    height: 70,
                    child: Transform.rotate(
                      angle: _heading * (3.14159 / 180),
                      child: _buildRiderIcon(),
                    ),
                  ),
                  if (targetMarker != null) targetMarker,
                ],
              ),
            ],
          ),
          _buildOverlayUI(hasActiveOrder, isPickupPhase),
          if (!_gpsReady)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              right: 20,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(LucideIcons.mapPin, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('Acquiring GPS... Showing default location',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 20,
            child: FloatingActionButton.small(
              onPressed: _fetchMyActiveOrder,
              backgroundColor: Colors.white,
              child: const Icon(LucideIcons.refreshCw, color: ProTheme.dark, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: ProTheme.primary.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
        ).animate(onPlay: (c) => c.repeat()).scale(
              begin: const Offset(1, 1),
              end: const Offset(2, 2),
              duration: 2000.ms,
              curve: Curves.easeOut,
            ).fadeOut(),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: ProTheme.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2)
            ],
          ),
          child: const Icon(LucideIcons.bike, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  Widget _buildTacticalMarker(IconData icon, Color color, bool pulsing) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (pulsing)
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
          ).animate(onPlay: (c) => c.repeat()).scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1.5, 1.5),
                duration: 1500.ms,
              ).fadeOut(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ],
    );
  }

  Widget _buildOverlayUI(bool hasActiveOrder, bool isPickupPhase) {
    if (!hasActiveOrder) {
      return Positioned(
        bottom: 30,
        left: 20,
        right: 20,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ProTheme.dark.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.radar, color: ProTheme.primary, size: 28),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("RADAR ACTIVE",
                        style: ProTheme.header.copyWith(
                            color: Colors.white, fontSize: 16, letterSpacing: 1.2)),
                    Text("No missions nearby. Stay operational.",
                        style: ProTheme.body.copyWith(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
    }

    final mission = _myActiveOrder!;
    return Positioned(
      bottom: 30,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ProTheme.dark.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: ProTheme.primary.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
                color: ProTheme.primary.withOpacity(0.1),
                blurRadius: 30,
                spreadRadius: 5)
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ProTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                      isPickupPhase ? LucideIcons.store : LucideIcons.home,
                      color: ProTheme.primary,
                      size: 24),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          isPickupPhase ? "COLLECT MISSION" : "DELIVERY MISSION",
                          style: ProTheme.label.copyWith(
                              color: ProTheme.primary,
                              letterSpacing: 1,
                              fontSize: 10)),
                      Text(
                          isPickupPhase
                              ? (mission['joined_vendor_name'] ?? 'Restaurant')
                              : (mission['joined_customer_name'] ?? 'Customer'),
                          style: ProTheme.header.copyWith(
                              color: Colors.white, fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final phone = isPickupPhase
                        ? mission['vendor_phone']
                        : mission['customer_phone'];
                    // Call logic would go here
                  },
                  icon: const Icon(LucideIcons.phone, color: Colors.white70),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.white10,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.mapPin, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        isPickupPhase
                            ? (mission['vendor_address'] ?? 'Proceed to Shop')
                            : (mission['delivery_address'] ?? 'Proceed to Client'),
                        style: ProTheme.body.copyWith(
                            color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().slideY(begin: 1, end: 0, curve: Curves.easeOutQuart);
  }
}

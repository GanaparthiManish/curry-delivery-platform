import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/supabase_config.dart';
import '../../core/location_store.dart';
import '../../core/services/notification_service.dart';
import '../menu/product_detail_screen.dart';
import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/widgets/banner_carousel.dart';
import '../../core/widgets/location_picker_screen.dart';
import '../orders/orders_screen.dart';
import '../cart/cart_screen.dart';
import '../profile/favorites_screen.dart';
import '../profile/profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'global_search_screen.dart';
import 'home_screen.dart'; 
import 'map_screen.dart';
import 'category_items_screen.dart';
import '../../core/menu_store.dart';
import '../../core/enums.dart';
import '../../core/pro_theme.dart';
import '../../core/cart_state.dart';
import 'package:latlong2/latlong.dart'; 
import '../../core/location_service.dart';
import '../../core/profile_store.dart';
import '../../core/address_store.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

class NewHomeScreen extends StatefulWidget {
  const NewHomeScreen({super.key});

  @override
  State<NewHomeScreen> createState() => _NewHomeScreenState();
}

class _NewHomeScreenState extends State<NewHomeScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _dbCategories = [];
  bool _isLoadingCategories = true;
  List<Map<String, dynamic>> _popularItems = [];
  List<Map<String, dynamic>> _normalItems = [];
  bool _isLoadingPopular = true;
  bool _isLoadingNormal = true;
  List<Map<String, dynamic>> _nearbyVendors = [];
  bool _isLoadingVendors = true;
  // Popular items vendor chooser
  List<Map<String, dynamic>> _allPopularItems = [];
  List<Map<String, dynamic>> _popularVendors = []; // vendors that have popular items within 5km
  String? _selectedPopularVendorId; // null = show all

  
  // Real-time handles
  RealtimeChannel? _productChannel;
  RealtimeChannel? _vendorChannel;
  List<Map<String, dynamic>> _addressResults = [];
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  bool _showAllCategoriesInline = false;

  @override
  void initState() {
    super.initState();
    _loadCachedHomeData();
    _fetchItemsDirectly();
    _fetchCategories();
    _initNotifications();
    _setupRealtime();
    
    // 🌍 Re-fetch when location changes
    LocationStore().addListener(_onLocationChanged);
    _onLocationChanged(); // Initial fetch
  }

  Future<void> _loadCachedHomeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? catData = prefs.getString('cached_db_categories');
      final String? popularData = prefs.getString('cached_popular_items');
      final String? normalData = prefs.getString('cached_normal_items');
      final String? vendorData = prefs.getString('cached_nearby_vendors');

      if (mounted) {
        setState(() {
          if (catData != null) {
            _dbCategories = List<Map<String, dynamic>>.from(jsonDecode(catData));
            _isLoadingCategories = false;
          }
          if (popularData != null) {
            _popularItems = List<Map<String, dynamic>>.from(jsonDecode(popularData));
            _isLoadingPopular = false;
          }
          if (normalData != null) {
            _normalItems = List<Map<String, dynamic>>.from(jsonDecode(normalData));
            _isLoadingNormal = false;
          }
          if (vendorData != null) {
            _nearbyVendors = List<Map<String, dynamic>>.from(jsonDecode(vendorData));
            _isLoadingVendors = false;
          }
        });
      }
    } catch (e) {
      debugPrint("Home cache load failed: $e");
    }
  }

  Future<void> _saveToCache(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
    } catch (e) {
      debugPrint("Cache save failed for key $key: $e");
    }
  }

  void _onLocationChanged() {
    if (mounted) {
      debugPrint(">>> [HOME] Location changed, re-fetching items...");
      _fetchItemsDirectly();
      _fetchNearbyVendors();
    }
  }

  void _setupRealtime() {
    _productChannel = SupabaseConfig.client.channel('public:products')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'products', callback: (payload) {
        debugPrint("Realtime Product Update: ${payload.toString()}");
        _fetchItemsDirectly();
      }).subscribe();

    _vendorChannel = SupabaseConfig.client.channel('public:vendors')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'vendors', callback: (payload) {
        debugPrint("Realtime Vendor Update: ${payload.toString()}");
        _fetchItemsDirectly();
      }).subscribe();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await SupabaseConfig.client
          .from('categories')
          .select('*')
          .order('priority', ascending: false);
      if (mounted) {
        setState(() {
          _dbCategories = List<Map<String, dynamic>>.from(response ?? []);
          _isLoadingCategories = false;
        });
        _saveToCache('cached_db_categories', _dbCategories);
      }
    } catch (e) {
      debugPrint("Category fetch error: $e");
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  void _initNotifications() {
    NotificationService.initialize();
  }

  @override
  void dispose() {
    LocationStore().removeListener(_onLocationChanged);
    if (_productChannel != null) SupabaseConfig.client.removeChannel(_productChannel!);
    if (_vendorChannel != null) SupabaseConfig.client.removeChannel(_vendorChannel!);
    super.dispose();
  }

  // Helper to calculate distance in KM using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
          c(lat1 * p) * c(lat2 * p) * 
          (1 - c((lon2 - lon1) * p))/2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _fetchItemsDirectly() async {
    try {
      final loc = LocationStore().selectedLocation;
      if (loc == null) {
        debugPrint(">>> [HOME] Waiting for coordinates...");
        if (mounted) {
          setState(() {
            _isLoadingPopular = _popularItems.isEmpty;
            _isLoadingNormal = _normalItems.isEmpty;
          });
        }
        return;
      }

      debugPrint(">>> [HOME] Fetching nearby vendors via RPC get_nearby_vendors_v24 for location: ${loc.latitude}, ${loc.longitude}");

      final vendorsResponse = await SupabaseConfig.client.rpc(
        'get_nearby_vendors_v24',
        params: {
          'p_lat': loc.latitude,
          'p_lng': loc.longitude,
        },
      );

      if (vendorsResponse == null) {
        debugPrint(">>> [HOME] Nearby vendors RPC returned null");
        if (mounted) {
          setState(() {
            _popularItems = [];
            _normalItems = [];
            _isLoadingPopular = false;
            _isLoadingNormal = false;
          });
        }
        return;
      }

      final List rawVendors = vendorsResponse as List;
      final List<String> vendorIds = [];
      final Map<String, Map<String, dynamic>> vendorMap = {};
      
      for (var v in rawVendors) {
        final Map<String, dynamic> vendor = Map<String, dynamic>.from(v);
        final distVal = vendor['distance_km'] ?? vendor['distance'] ?? 0;
        final double dist = double.tryParse(distVal.toString()) ?? 0.0;
        
        // 🌍 Strict 5KM Proximity Enforcement
        if (dist <= 5.0) {
          final id = vendor['id']?.toString();
          if (id != null) {
            vendorIds.add(id);
            vendorMap[id] = vendor;
          }
        }
      }

      if (vendorIds.isEmpty) {
        debugPrint(">>> [HOME] No vendors found within 5km");
        if (mounted) {
          setState(() {
            _popularItems = [];
            _normalItems = [];
            _isLoadingPopular = false;
            _isLoadingNormal = false;
          });
        }
        return;
      }

      debugPrint(">>> [HOME] Querying products for nearby vendors: $vendorIds");

      final productsResponse = await SupabaseConfig.client
          .from('products')
          .select()
          .eq('is_active', true)
          .inFilter('vendor_id', vendorIds)
          .limit(500);

      if (productsResponse == null) {
        debugPrint(">>> [HOME] Products REST query returned null");
        if (mounted) {
          setState(() {
            _popularItems = [];
            _allPopularItems = [];
            _normalItems = [];
            _isLoadingPopular = false;
            _isLoadingNormal = false;
          });
        }
        return;
      }

      final List rawProducts = productsResponse as List;
      final List<Map<String, dynamic>> filteredItems = [];

      for (var p in rawProducts) {
        final Map<String, dynamic> item = Map<String, dynamic>.from(p);
        final vendorId = item['vendor_id']?.toString();
        if (vendorId == null) continue;

        final vendor = vendorMap[vendorId];
        if (vendor == null) continue;

        // ── STRICT 5KM DART-SIDE HAVERSINE RE-CHECK ──────────────────
        // The RPC distance_km can be wrong when vendor lat/lng is null in DB.
        // We recompute from vendor's stored coordinates to enforce strictly.
        final vLat = double.tryParse((vendor['latitude'] ?? vendor['lat'] ?? 0).toString());
        final vLng = double.tryParse((vendor['longitude'] ?? vendor['lng'] ?? 0).toString());
        double dist;
        if (vLat != null && vLng != null && vLat != 0.0 && vLng != 0.0) {
          dist = _calculateDistance(loc.latitude, loc.longitude, vLat, vLng);
        } else {
          // Fall back to RPC-reported value
          dist = double.tryParse(
              (vendor['distance_km'] ?? vendor['distance'] ?? 99).toString()) ?? 99.0;
        }

        // Hard 5km gate — skip this item if vendor is beyond 5km
        if (dist > 5.0) {
          debugPrint(">>> [5KM GATE] Vendor ${vendor['name']} at ${dist.toStringAsFixed(2)}km — REJECTED");
          continue;
        }

        // Build trusted_vendor metadata
        item['trusted_vendor'] = {
          'vendor_id': vendor['id'],
          'vendor_name': vendor['name'],
          'price': item['price'],
          'rating': vendor['rating'] ?? 4.0,
          'distance': dist,
          'distance_km': dist,
          'eta_mins': "${(dist * 5 + 15).toInt()}",
        };
        item['vendor_name'] = vendor['name'];
        item['_vendor_dist'] = dist; // store for sorting

        // Map category name
        final catId = item['category_id']?.toString();
        String catName = '';
        if (catId != null && _dbCategories.isNotEmpty) {
          final catMatch = _dbCategories.firstWhere(
            (c) => c['id']?.toString() == catId,
            orElse: () => <String, dynamic>{},
          );
          catName = catMatch['name']?.toString() ?? '';
        }
        item['category_name'] = catName;

        filteredItems.add(item);
      }

      debugPrint(">>> [HOME] Items passing strict 5km gate: ${filteredItems.length}");

      // ── POPULAR ITEMS (all vendors, all tagged popular within 5km) ─
      final allPopular = filteredItems.where((p) =>
        (p['is_popular'] == true) ||
        (p['item_type']?.toString().toUpperCase() == 'POPULAR_ITEM')
      ).toList()
        ..sort((a, b) {
          final dA = (a['_vendor_dist'] as double?) ?? 99.0;
          final dB = (b['_vendor_dist'] as double?) ?? 99.0;
          return dA.compareTo(dB);
        });

      // Build list of vendors that have popular items, sorted by distance
      final Map<String, Map<String, dynamic>> seenVendors = {};
      for (final item in allPopular) {
        final vid = item['vendor_id']?.toString();
        if (vid != null && !seenVendors.containsKey(vid)) {
          seenVendors[vid] = {
            'id': vid,
            'name': item['vendor_name'] ?? '',
            'dist': item['_vendor_dist'] ?? 99.0,
          };
        }
      }
      final popularVendors = seenVendors.values.toList()
        ..sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));

      // ── NORMAL ITEMS ──────────────────────────────────────────────
      final normal = filteredItems.where((p) =>
        (p['is_popular'] != true) &&
        (p['item_type']?.toString().toUpperCase() != 'POPULAR_ITEM')
      ).toList();

      if (mounted) {
        setState(() {
          _allPopularItems = List<Map<String, dynamic>>.from(allPopular);
          _popularItems = List<Map<String, dynamic>>.from(allPopular);
          _popularVendors = popularVendors;
          // Reset vendor selection if vendor list changed
          if (_selectedPopularVendorId != null &&
              !seenVendors.containsKey(_selectedPopularVendorId)) {
            _selectedPopularVendorId = null;
          }
          _normalItems = List<Map<String, dynamic>>.from(normal);
          _isLoadingPopular = false;
          _isLoadingNormal = false;
        });
        _saveToCache('cached_popular_items', _allPopularItems);
        _saveToCache('cached_normal_items', _normalItems);
      }
    } catch (e) {
      debugPrint(">>> [HOME] Direct Fetch error: $e");
      if (mounted) {
        setState(() {
          _isLoadingPopular = false;
          _isLoadingNormal = false;
        });
      }
    }
  }


  Future<void> _fetchNearbyVendors() async {
    try {
      final store = LocationStore();
      if (store.selectedLocation == null) {
        setState(() => _isLoadingVendors = false);
        return;
      }

      debugPrint(">>> [HOME] Fetching nearby vendors via RPC for ${store.selectedLocation!.latitude}, ${store.selectedLocation!.longitude}");

      // 🛰️ USE LOCATION-AWARE VENDOR RPC
      final response = await SupabaseConfig.client.rpc(
        'get_nearby_vendors_v24',
        params: {
          'p_lat': store.selectedLocation!.latitude,
          'p_lng': store.selectedLocation!.longitude,
        },
      ).timeout(const Duration(seconds: 15));

      if (response == null) {
        if (mounted) setState(() => _isLoadingVendors = false);
        return;
      }

      final List<Map<String, dynamic>> vendors = List<Map<String, dynamic>>.from(response).where((v) {
        final distVal = v['distance_km'] ?? v['distance'] ?? 0;
        final dist = double.tryParse(distVal.toString()) ?? 0;
        return dist <= 15.0;
      }).toList();

      if (mounted) {
        setState(() {
          _nearbyVendors = vendors;
          _isLoadingVendors = false;
        });
        _saveToCache('cached_nearby_vendors', _nearbyVendors);
      }
    } catch (e) {
      debugPrint("Vendors fetch error: $e");
      if (mounted) setState(() => _isLoadingVendors = false);
    }
  }

  Widget _buildHomeFeed() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchCategories();
        await _fetchItemsDirectly();
        await _fetchNearbyVendors();
      },
      color: const Color(0xFF2E7D32),
      child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              _buildLocationSelector(),
              _buildSearchBar(),
              const BannerCarousel(),
              _buildCategories(),
              _buildPopularNearYou(),
              _buildNormalItems(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocationStore(),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomeFeed(),
                const MapScreen(), // This is the "Old Explore"
                const OrdersScreen(showBack: false),
                const CartScreen(isTab: true),
                const ProfileScreen(),
              ],
            ),
          ),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Removed Hamburger Menu per User Request
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'UNIV',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: 0,
                    ),
                  ),
                  Text(
                    'FOODS',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFFF6D00),
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              Container(
                height: 4,
                width: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6D00),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/notifications'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.notifications_active_outlined, color: ProTheme.primary, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSelector() {
    final store = LocationStore();
    final address = store.selectedAddress.isNotEmpty ? store.selectedAddress : "Select your location";
    final label = store.selectedLabel.isNotEmpty ? store.selectedLabel : "Deliver to";

    return InkWell(
      onTap: () => _showAddressPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            const Icon(Icons.location_on, size: 20, color: Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Text(
              'Current Location  ',
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      address,
                      style: GoogleFonts.inter(
                        color: Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.black87),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.gps_fixed, size: 20, color: Color(0xFF2E7D32)),
              onPressed: () async {
                final pos = await LocationService.getCurrentPosition();
                if (pos != null) {
                  final addr = await LocationService.getAddressFromLatLng(pos.latitude, pos.longitude);
                  LocationStore().updateLocation(LatLng(pos.latitude, pos.longitude), addr, "Current Location");
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const GlobalSearchScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.search, color: ProTheme.primary),
              const SizedBox(width: 8),
              Text(
                'Search for food, items or categories',
                style: GoogleFonts.inter(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildCategories() {
    final defaultCategories = [
      {'name': 'Tiffins', 'image_url': 'https://img.icons8.com/color/96/dosa.png', 'color': const Color(0xFFFFF7E6)},
      {'name': 'Juices', 'image_url': 'https://img.icons8.com/color/96/orange-juice.png', 'color': const Color(0xFFEFFFF4)},
      {'name': 'Fast Food', 'image_url': 'https://img.icons8.com/color/96/hamburger.png', 'color': const Color(0xFFFFF0E6)},
      {'name': 'Bakery', 'image_url': 'https://img.icons8.com/color/96/cake.png', 'color': const Color(0xFFF9F0FF)},
      {'name': 'Veg Curries', 'image_url': 'https://img.icons8.com/color/96/paneer.png', 'color': const Color(0xFFEFFFF4), 'dot': Colors.green},
      {'name': 'Non-Veg Curries', 'image_url': 'https://img.icons8.com/color/96/roasted-chicken.png', 'color': const Color(0xFFFFF0E6), 'dot': Colors.red},
      {'name': 'Street Food', 'image_url': 'https://img.icons8.com/color/96/samosa.png', 'color': const Color(0xFFFFF7E6)},
    ];

    List<Map<String, dynamic>> displayCategories = [];
    if (_dbCategories.isNotEmpty) {
      displayCategories = List.from(_dbCategories);
    } else {
      displayCategories = List.from(defaultCategories);
    }

    // Determine what items to show in the 4-column grid
    List<Map<String, dynamic>> itemsToShow = [];
    bool showMoreCard = false;
    bool isExpanded = _showAllCategoriesInline;

    if (!isExpanded) {
      // Show first 7 items + 1 "More" item
      if (displayCategories.length > 7) {
        itemsToShow = displayCategories.sublist(0, 7);
        showMoreCard = true;
      } else {
        itemsToShow = displayCategories;
      }
    } else {
      // Show all items + 1 "Less" item at the end
      itemsToShow = List.from(displayCategories);
    }

    final int totalCount = itemsToShow.length + (showMoreCard ? 1 : (isExpanded ? 1 : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "What's on your mind?",
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Explore handpicked categories near you",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showAllCategoriesInline = !_showAllCategoriesInline;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(
                        isExpanded ? "Show Less" : "See All", 
                        style: GoogleFonts.inter(
                          fontSize: 12, 
                          fontWeight: FontWeight.w700, 
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.arrow_forward_ios_rounded, 
                        color: const Color(0xFF2E7D32), 
                        size: 10
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.74,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: totalCount,
            itemBuilder: (context, index) {
              // Check if this index is a "More" or "Less" action card
              if (showMoreCard && index == 7) {
                return _buildCategoryCircularItem(
                  {'name': 'More', 'image_url': 'MORE', 'color': const Color(0xFFF5F5F5)}, 
                  isAction: true,
                  isLess: false,
                );
              }
              if (isExpanded && index == itemsToShow.length) {
                return _buildCategoryCircularItem(
                  {'name': 'Less', 'image_url': 'LESS', 'color': const Color(0xFFF5F5F5)}, 
                  isAction: true,
                  isLess: true,
                );
              }

              final cat = itemsToShow[index];
              return _buildCategoryCircularItem(cat, isAction: false, isLess: false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildViewAllCardFullWidth() {
    return InkWell(
      onTap: () => _showAllCategories(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8F1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8F5E9)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.grid_view_rounded, color: Color(0xFF2E7D32), size: 20),
            const SizedBox(width: 8),
            Text("View All Categories", style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32))),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCircularItem(
    Map<String, dynamic> cat, {
    required bool isAction,
    required bool isLess,
  }) {
    final String catName = cat['name']?.toString() ?? '';
    
    return GestureDetector(
      onTap: () {
        if (isAction) {
          setState(() {
            _showAllCategoriesInline = !_showAllCategoriesInline;
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CategoryItemsScreen(
                categoryName: catName,
                categoryId: cat['id']?.toString(),
              ),
            ),
          );
        }
      },
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cat['color'] as Color? ?? const Color(0xFFFFF7E6),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: isAction
                    ? Icon(
                        isLess ? Icons.keyboard_arrow_up_rounded : Icons.grid_view_rounded, 
                        color: const Color(0xFF2E7D32), 
                        size: 24
                      )
                    : CachedNetworkImage(
                        imageUrl: SupabaseConfig.imageUrl(cat['image_url'] ?? ''),
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const SizedBox.shrink(),
                        errorWidget: (context, url, error) => const Icon(Icons.fastfood, color: Colors.grey),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            catName,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPopularNearYou() {
    if (_isLoadingPopular) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader("Popular Near You"),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              itemBuilder: (context, index) => _buildPopularShimmer(),
            ),
          ),
        ],
      );
    }

    if (_allPopularItems.isEmpty) return const SizedBox.shrink();

    // Display all popular items without filtering
    final List<Map<String, dynamic>> displayItems = _allPopularItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Popular Near You",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Popular items horizontal list ────────────────────────────
        SizedBox(
          height: 255,
          child: displayItems.isEmpty
              ? Center(
                  child: Text(
                    "No popular items found",
                    style: GoogleFonts.inter(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: displayItems.length,
                  itemBuilder: (context, index) {
                    return _buildPopularItemCard(displayItems[index]);
                  },
                ),
        ),
      ],
    );
  }


  Widget _buildPopularShimmer() {
    return Container(
      width: 160,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }





  Widget _buildVendorCard(Map<String, dynamic> vendor) {
    final img = SupabaseConfig.imageUrl(vendor['image_url']);
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/menu', arguments: vendor);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5)),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: CachedNetworkImage(
                imageUrl: img,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (c, u) => Container(
                  height: 160,
                  width: double.infinity,
                  color: Colors.grey[100],
                ),
                errorWidget: (c, u, e) => Container(
                  height: 160,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: const Icon(Icons.restaurant, color: Colors.grey),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(vendor['name'] ?? 'Restaurant', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
                            Text(" ${vendor['rating'] ?? '4.2'}", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                            Text(" • ${((vendor['distance'] ?? 0) as double).toStringAsFixed(1)} km", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFFF1F8F1), borderRadius: BorderRadius.circular(12)),
                    child: Text("30-40 min", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2E7D32))),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📍 ADDRESS PICKER LOGIC (BLINKIT STYLE REDESIGN)
  void _showAddressPicker(BuildContext context) {
    final uid = SupabaseConfig.currentUid;
    final store = LocationStore();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      "Select a location",
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ProTheme.primary.withOpacity(0.3), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                  ),
                  child: TextField(
                    onChanged: (v) async {
                      if (v.length > 2) {
                        final results = await LocationService.searchPlaces(v);
                        setModalState(() => _addressResults = results);
                      } else {
                        setModalState(() => _addressResults = []);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Search for area, street name...',
                      hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
                      prefixIcon: const Icon(Icons.search, color: ProTheme.primary, size: 22),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Search Results
                    if (_addressResults.isNotEmpty) ...[
                      Text("SEARCH RESULTS", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                      const SizedBox(height: 12),
                      ..._addressResults.map((res) => Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[100]!)),
                        child: ListTile(
                          leading: const Icon(Icons.location_on_outlined, color: ProTheme.primary),
                          title: Text(res['display_name'] ?? "", maxLines: 2, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                          onTap: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LocationPickerScreen(
                                  initialPosition: LatLng(
                                    (res['lat'] as num?)?.toDouble() ?? 0,
                                    (res['lon'] as num?)?.toDouble() ?? 0,
                                  ),
                                ),
                              ),
                            );
                            if (result != null) {
                              LocationStore().updateLocation(
                                LatLng(result['lat'], result['lng']),
                                result['address'],
                                result['tag'],
                                house: result['details'],
                                pincode: result['pincode'],
                                phone: result['phone'],
                              );
                            }
                          },
                        ),
                      )),
                      const SizedBox(height: 16),
                    ],

                    // Quick Actions
                    _buildQuickActionCard(
                      icon: Icons.my_location_rounded,
                      title: "Use current location",
                      subtitle: store.selectedAddress,
                      onTap: () async {
                        Navigator.pop(context);
                        final pos = await LocationService.getCurrentPosition();
                        if (pos != null) {
                          final addr = await LocationService.getAddressFromLatLng(pos.latitude, pos.longitude);
                          LocationStore().updateLocation(LatLng(pos.latitude, pos.longitude), addr, "Current Location");
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildQuickActionCard(
                      icon: Icons.add_rounded,
                      title: "Add Address",
                      onTap: () async {
                        Navigator.pop(context);
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LocationPickerScreen())
                        );
                        if (result != null) {
                          LocationStore().updateLocation(
                            LatLng(result['lat'], result['lng']),
                            result['address'],
                            result['tag'],
                            house: result['details'],
                            pincode: result['pincode'],
                            phone: result['phone'],
                          );

                          // 🚀 REAL-TIME PERSISTENCE: Save to Supabase
                          if (uid != null) {
                            AddressStore().saveAddress({
                              'label': result['tag'],
                              'address_line': "${result['details'] != null && result['details'].isNotEmpty ? result['details'] + ', ' : ''}${result['address']}",
                              'pincode': result['pincode'],
                              'phone': result['phone'],
                              'latitude': result['lat'],
                              'longitude': result['lng'],
                            });
                          }
                        }
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    Text("SAVED ADDRESSES", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
                    const SizedBox(height: 16),
                    
                    if (uid != null)
                      StreamBuilder<List<Map<String, dynamic>>>(
                        stream: SupabaseConfig.client.from('user_addresses').stream(primaryKey: ['id']).eq('user_id', uid),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return _buildEmptyState();
                          }
                          return Column(
                            children: snapshot.data!.map((a) => _buildAddressCard(a)).toList(),
                          );
                        }
                      )
                    else
                      _buildLoginPrompt(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: ProTheme.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: ProTheme.primary)),
                  if (subtitle != null)
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(a['label'] == 'Home' ? Icons.home_rounded : Icons.location_on_rounded, color: Colors.grey[400], size: 28),
              const SizedBox(height: 4),
              Builder(
                builder: (context) {
                  final currentLoc = LocationStore().selectedLocation;
                  if (currentLoc != null && a['latitude'] != null && a['longitude'] != null) {
                    final dist = const Distance().as(LengthUnit.Meter, currentLoc, LatLng(a['latitude'], a['longitude'])) / 1000.0;
                    return Text("${dist.toStringAsFixed(1)} km", style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[400]));
                  }
                  return Text("--- km", style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[400]));
                }
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a['label'] ?? a['title'] ?? "Address", style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text("${a['house_number'] ?? ''} ${a['address_line'] ?? ''}".trim(), 
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text("Phone: ${a['phone'] ?? a['phone_number'] ?? 'N/A'}", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
                const SizedBox(height: 12),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _showAddressDetailsDialog(
                        label: a['label'] ?? 'Address',
                        address: a['address_line'] ?? '',
                        lat: (a['latitude'] as num?)?.toDouble() ?? 0,
                        lng: (a['longitude'] as num?)?.toDouble() ?? 0,
                        pincode: a['pincode']?.toString() ?? '',
                      ),
                      child: _buildSmallActionBtn(Icons.more_horiz),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Address shared!")));
                      },
                      child: _buildSmallActionBtn(Icons.share_outlined),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () async {
                        if (a['id'] != null) {
                          await SupabaseConfig.client.from('user_addresses').delete().eq('id', a['id']);
                        }
                      },
                      child: _buildSmallActionBtn(Icons.delete_outline),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _setAddress(
                          a['label'] ?? "Address",
                          a['address_line'] ?? '',
                          house: a['house_number']?.toString() ?? '',
                          pin: a['pincode']?.toString() ?? '',
                          phone: (a['phone'] ?? a['phone_number'])?.toString() ?? '',
                          lat: (a['latitude'] as num?)?.toDouble(),
                          lng: (a['longitude'] as num?)?.toDouble(),
                        );
                      },
                      child: Text("SELECT", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: ProTheme.primary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionBtn(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Icon(icon, size: 16, color: ProTheme.primary),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32.0),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.location_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text("No saved addresses yet.", style: GoogleFonts.inter(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildViewAllCard() {
    return InkWell(
      onTap: () => _showAllCategories(),
      child: Container(
        width: 100,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8F5E9)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.grid_view_rounded, color: Color(0xFF2E7D32), size: 24),
            ),
            const SizedBox(height: 8),
            Text("View All", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32))),
          ],
        ),
      ),
    );
  }

  void _showAllCategories() {
    final defaultCategories = [
      {'name': 'All Items', 'image_url': 'https://img.icons8.com/color/96/food-receiver.png'},
      {'name': 'Tiffins', 'image_url': 'https://img.icons8.com/color/96/dosa.png'},
      {'name': 'Meals', 'image_url': 'https://img.icons8.com/color/96/thali.png'},
      {'name': 'Biryani', 'image_url': 'https://img.icons8.com/color/96/biryani.png'},
      {'name': 'Snacks', 'image_url': 'https://img.icons8.com/color/96/samosa.png'},
      {'name': 'Non-Veg', 'image_url': 'https://img.icons8.com/color/96/roasted-chicken.png'},
      {'name': 'Roti', 'image_url': 'https://img.icons8.com/color/96/naan.png'},
      {'name': 'Juice', 'image_url': 'https://img.icons8.com/color/96/orange-juice.png'},
      {'name': 'Bakery', 'image_url': 'https://img.icons8.com/color/96/cake.png'},
      {'name': 'Ice Cream', 'image_url': 'https://img.icons8.com/color/96/ice-cream-bowl.png'},
      {'name': 'Drinks', 'image_url': 'https://img.icons8.com/color/96/cocktail.png'},
    ];

    List<Map<String, dynamic>> displayCategories = [];
    if (_dbCategories.isNotEmpty) {
      displayCategories = [{'name': 'All Items', 'image_url': 'https://img.icons8.com/color/96/food-receiver.png'}];
      displayCategories.addAll(_dbCategories);
    } else {
      displayCategories = defaultCategories;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("All Categories", style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w900)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: displayCategories.length,
                itemBuilder: (context, index) {
                  final cat = displayCategories[index];
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CategoryItemsScreen(
                            categoryName: cat['name'] ?? '',
                            categoryId: cat['name'] == 'All Items' ? null : cat['id']?.toString(),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
                        border: Border.all(color: Colors.grey[100]!),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CachedNetworkImage(
                            imageUrl: SupabaseConfig.imageUrl(cat['image_url'] ?? ''),
                            height: 60,
                            width: 60,
                            placeholder: (context, url) => const SizedBox.shrink(),
                            errorWidget: (context, url, error) => const Icon(Icons.fastfood, size: 40),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(cat['name'] ?? '', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text("Login to see your saved addresses", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => Navigator.pushNamed(context, '/login'), child: const Text("LOGIN")),
        ],
      ),
    );
  }

  void _showAddressDetailsDialog({
    String label = 'Current Location',
    required double lat,
    required double lng,
    required String address,
    required String pincode,
  }) {
    final store = LocationStore();
    final houseCtrl = TextEditingController(text: store.houseNumber);
    final pinCtrl = TextEditingController(text: pincode.isNotEmpty ? pincode : store.pincode);
    final phoneCtrl = TextEditingController(text: store.phone.isNotEmpty ? store.phone : (ProfileStore().profile?['phone'] ?? ''));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivery Details', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(address, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextField(controller: houseCtrl, decoration: const InputDecoration(labelText: "House/Flat No.")),
            TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: "Pincode"), keyboardType: TextInputType.number),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phone Number"), keyboardType: TextInputType.phone),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  Navigator.pop(ctx);
                  _setAddress(label, address, house: houseCtrl.text, pin: pinCtrl.text, phone: phoneCtrl.text, lat: lat, lng: lng);
                },
                child: const Text("Confirm Location"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setAddress(String label, String addr, {String house = '', String pin = '', String phone = '', double? lat, double? lng}) async {
    if (lat != null && lng != null) {
      await LocationStore().updateLocation(LatLng(lat, lng), addr, label, house: house, pincode: pin, phone: phone);
    }
  }

  Widget _buildPopularItemCard(Map<String, dynamic> item) {
    final img = SupabaseConfig.imageUrl(item['image_url']);
    final vendor = item['trusted_vendor'];
    final price = vendor?['price'] ?? item['price'] ?? 0;
    
    // Fix field mapping: distance_km from RPC
    final distVal = vendor?['distance_km'] ?? vendor?['distance'] ?? 0;
    final distDouble = double.tryParse(distVal.toString()) ?? 0;
    final distance = distDouble.toStringAsFixed(1);
    
    final calculatedEta = (distDouble * 5 + 15).toInt();
    final eta = vendor?['eta_mins'] ?? calculatedEta.toString();

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: item),
          ),
        );
      },
      child: Container(
        width: 170, // Fixed width for horizontal scroll
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: img,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[100],
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.fastfood, color: Colors.grey, size: 40),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['name'] ?? 'Delicious Item',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: Color(0xFFFFB300)),
                    Text(
                      " ${vendor?['rating'] ?? '4.2'}",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      " • $distance km",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F8F1), borderRadius: BorderRadius.circular(4)),
                  child: Text("Deliver in ${eta}m ✓", style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32))),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "₹$price",
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProductDetailScreen(product: item),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'ADD',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) => setState(() => _selectedIndex = index),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFFF6D00),
      unselectedItemColor: Colors.grey[400],
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
      unselectedLabelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.normal),
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
        const BottomNavigationBarItem(icon: Icon(Icons.explore_outlined), label: "Explore"),
        const BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), label: "Orders"),
        BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_cart_outlined),
                ListenableBuilder(
                  listenable: GlobalCart(),
                  builder: (context, _) {
                    final count = GlobalCart().itemCount;
                    if (count == 0) return const SizedBox();
                    return Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF6D00),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
            label: "Cart"),
        const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),
      ],
    );
  }

  Widget _buildNormalItems() {
    if (_normalItems.isEmpty && !_isLoadingNormal) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedCategoryName != null 
                    ? "Other ${_selectedCategoryName}s"
                    : 'Other Items',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              Text(
                "View All",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6D00),
                ),
              ),
            ],
          ),
        ),
        if (_isLoadingNormal)
          const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _normalItems.length,
            itemBuilder: (context, index) {
              final item = _normalItems[index];
              return _buildItemCard(item);
            },
          ),
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final vendor = item['trusted_vendor'] ?? {};
    final distVal = vendor['distance_km'] ?? vendor['distance'] ?? 0;
    final distDouble = double.tryParse(distVal.toString()) ?? 0;
    final distance = distDouble.toStringAsFixed(1);
    final calculatedEta = (distDouble * 5 + 15).toInt();
    final eta = vendor['eta_mins'] ?? calculatedEta.toString();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailScreen(product: item),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: CachedNetworkImage(
                  imageUrl: SupabaseConfig.imageUrl(item['image_url']),
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => Container(color: Colors.grey[100]),
                  errorWidget: (c, u, e) => Container(color: Colors.grey[100], child: const Icon(Icons.fastfood)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'],
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vendor['vendor_name'] ?? 'Restaurant',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: ProTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star, size: 12, color: Colors.green),
                              const SizedBox(width: 2),
                              Text(
                                vendor['rating']?.toString() ?? '4.5',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green[700]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                          Text(
                            '$distance km • $eta mins',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₹${item['price']}',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: ProTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'ADD',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Colors.black87,
        ),
      ),
    );
  }
}

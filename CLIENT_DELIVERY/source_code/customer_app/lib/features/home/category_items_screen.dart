import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/supabase_config.dart';
import '../../core/location_store.dart';
import '../../core/pro_theme.dart';
import '../menu/product_detail_screen.dart';

class CategoryItemsScreen extends StatefulWidget {
  final String categoryName;
  final String? categoryId;

  const CategoryItemsScreen({
    super.key,
    required this.categoryName,
    this.categoryId,
  });

  @override
  State<CategoryItemsScreen> createState() => _CategoryItemsScreenState();
}

class _CategoryItemsScreenState extends State<CategoryItemsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  Future<void> _fetchItems() async {
    try {
      final loc = LocationStore().selectedLocation;
      if (loc == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      debugPrint(">>> [CATEGORY] Fetching nearby vendors via RPC for location: ${loc.latitude}, ${loc.longitude}");

      final vendorsResponse = await SupabaseConfig.client.rpc(
        'get_nearby_vendors_v24',
        params: {
          'p_lat': loc.latitude,
          'p_lng': loc.longitude,
        },
      );

      if (vendorsResponse == null) {
        if (mounted) {
          setState(() {
            _items = [];
            _isLoading = false;
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
        if (mounted) {
          setState(() {
            _items = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Fetch categories for name-based category matching if needed
      List<Map<String, dynamic>> categories = [];
      if (widget.categoryId == null && widget.categoryName != 'All Items' && widget.categoryName != 'Popular Near You') {
        final catRes = await SupabaseConfig.client.from('categories').select();
        if (catRes != null) {
          categories = List<Map<String, dynamic>>.from(catRes);
        }
      }

      final productsResponse = await SupabaseConfig.client
          .from('products')
          .select()
          .eq('is_active', true)
          .inFilter('vendor_id', vendorIds)
          .limit(300);

      if (productsResponse == null) {
        if (mounted) {
          setState(() {
            _items = [];
            _isLoading = false;
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

        final distVal = vendor['distance_km'] ?? vendor['distance'] ?? 0;
        final double dist = double.tryParse(distVal.toString()) ?? 0.0;

        // Filter by category if not 'All Items' or 'Popular Near You'
        if (widget.categoryName != 'All Items' && widget.categoryName != 'Popular Near You') {
          final itemCatId = item['category_id']?.toString();
          final widgetCatId = widget.categoryId?.toString();
          
          if (widgetCatId != null) {
            if (itemCatId != widgetCatId) continue;
          } else {
            final catMatch = categories.firstWhere(
              (c) => c['id']?.toString() == itemCatId,
              orElse: () => <String, dynamic>{},
            );
            final catName = catMatch['name']?.toString() ?? '';
            if (!catName.toLowerCase().contains(widget.categoryName.toLowerCase())) {
              continue;
            }
          }
        }

        // Build trusted_vendor in memory
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
        filteredItems.add(item);
      }

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(filteredItems);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(">>> [CATEGORY] Fetch error: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final popularItems = _items.where((p) => 
      (p['is_popular'] == true) || 
      (p['item_type']?.toString().toUpperCase() == 'POPULAR_ITEM')
    ).toList();

    final normalItems = _items.where((p) => 
      (p['is_popular'] != true) && 
      (p['item_type']?.toString().toUpperCase() != 'POPULAR_ITEM')
    ).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.categoryName,
          style: GoogleFonts.outfit(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)))
          : _items.isEmpty
              ? Center(
                  child: Text(
                    "No items found for this category near you.",
                    style: GoogleFonts.inter(color: Colors.grey[600]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (popularItems.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          "Popular Choice 🔥",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      ...popularItems.map((item) => _buildItemCard(item)).toList(),
                      const SizedBox(height: 16),
                    ],
                    if (normalItems.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 12),
                        child: Text(
                          "Other Items",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      ...normalItems.map((item) => _buildItemCard(item)).toList(),
                    ],
                  ],
                ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final vendor = item['trusted_vendor'] ?? {};
    final distVal = vendor['distance_km'] ?? vendor['distance'] ?? 0;
    final distance = (double.tryParse(distVal.toString()) ?? 0).toStringAsFixed(1);
    final eta = vendor['eta_mins'] ?? "30";
    
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
}

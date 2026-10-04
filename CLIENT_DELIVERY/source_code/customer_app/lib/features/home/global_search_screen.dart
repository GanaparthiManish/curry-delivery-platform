import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/pro_theme.dart';
import '../../core/supabase_config.dart';
import '../../core/location_store.dart';
import '../menu/menu_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  String? _errorMessage;
  String _currentQuery = "";
  bool _isLoading = false;
  Timer? _debounce;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  void _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _errorMessage = null;
          _currentQuery = "";
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentQuery = cleanQuery;
      });
    }

    try {
      final loc = LocationStore().selectedLocation;
      if (loc == null) {
        throw Exception("Location not available. Please enable GPS.");
      }

      debugPrint(">>> [SEARCH] Searching for \"$cleanQuery\" near ${loc.latitude}, ${loc.longitude}");

      // 🚀 USE NEW LOCATION-AWARE RPC
      final response = await SupabaseConfig.client.rpc('search_items_near_you_v2', params: {
        'p_query': cleanQuery,
        'p_lat': loc.latitude,
        'p_lng': loc.longitude,
      });

      if (response == null) {
        if (mounted) {
          setState(() {
            _results = [];
            _isLoading = false;
            _errorMessage = "No menu items or shops found for \"$cleanQuery\" in your area.";
          });
        }
        return;
      }

      final List rawList = response as List;
      final List<Map<String, dynamic>> combined = [];

      for (var item in rawList) {
        // The RPC returns products with their trusted_vendor info
        combined.add({
          ...item,
          'type': 'product',
          'vendors': item['trusted_vendor'],
        });
      }

      if (mounted) {
        setState(() {
          _results = combined;
          _isLoading = false;
          if (combined.isEmpty) {
            _errorMessage = "No menu items or shops found for \"$cleanQuery\" in your area.";
          }
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().contains("Location") ? e.toString() : "Unable to complete search. Try again.";
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Container(
          height: 45,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onSearchChanged,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: "Search curries (v1.1.0+22)...",
              hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 13),
              prefixIcon: const Icon(LucideIcons.search, size: 18, color: ProTheme.primary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.amber[50],
              child: Text(
                _errorMessage!,
                style: GoogleFonts.inter(
                  color: Colors.amber[900],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: ProTheme.primary))
                : _results.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_results.any((e) => e['type'] == 'vendor')) ...[
                            _buildSectionHeader("AVAILABLE SHOPS"),
                            ..._results
                                .where((e) => e['type'] == 'vendor')
                                .map((v) => _buildVendorResult(v)),
                            const SizedBox(height: 24),
                          ],
                          if (_results.any((e) => e['type'] == 'product')) ...[
                            _buildSectionHeader("MATCHING ITEMS IN MENU"),
                            ..._results
                                .where((e) => e['type'] == 'product')
                                .map((p) => _buildProductResult(p)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Opacity(
              opacity: 0.1,
              child: Icon(LucideIcons.search, size: 100, color: ProTheme.primary),
            ),
            const SizedBox(height: 24),
            Text(
              _searchController.text.isEmpty
                  ? "Looking for something delicious?"
                  : "No specialized results found",
              textAlign: TextAlign.center,
              style:
                  GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              _searchController.text.isEmpty
                  ? "Enter a dish, restaurant, or cuisine\nin the search bar above"
                  : "We couldn't find matches for \"${_searchController.text}\". Try checking the spelling or searching for another dish.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendorResult(Map<String, dynamic> v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: CachedNetworkImageProvider(
                SupabaseConfig.imageUrl(v['banner_url'] ?? v['image_url'] ?? v['image']),
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(v['shop_name'] ?? v['name'] ?? 'Restaurant',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
            if (v['reason'] != null)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(4)),
                child: Text(v['reason'].toString().toUpperCase(), 
                  style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber[900])),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            const Icon(Icons.star, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Text("${v['rating'] ?? '4.2'} • ${v['cuisine_type'] ?? 'Multi-cuisine'}",
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: ProTheme.primary),
        onTap: () => Navigator.pushNamed(context, '/menu', arguments: v),
      ),
    );
  }

  Widget _buildProductResult(Map<String, dynamic> p) {
    final vendor = p['vendors'] ?? {};
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: SupabaseConfig.imageUrl(p['image_url'] ?? p['image']),
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            placeholder: (c, u) => Container(color: Colors.grey[200]),
            errorWidget: (c, e, s) => Container(color: Colors.grey[100], child: const Icon(Icons.fastfood)),
          ),
        ),
        title: Text(p['name'],
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("From ${vendor['name'] ?? 'Restaurant'}",
                style: GoogleFonts.inter(fontSize: 12, color: ProTheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(p['description'] ?? "Freshly prepared delicious item.",
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(p['is_veg'] == true ? "Veg" : "Non-Veg",
                style: GoogleFonts.inter(fontSize: 11, color: p['is_veg'] == true ? Colors.green : Colors.red)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("₹${p['price']}",
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black)),
            const SizedBox(height: 4),
            Text("ORDER NOW", 
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: ProTheme.secondary)),
          ],
        ),
        onTap: () {
          Navigator.pushNamed(context, '/product_detail', arguments: p);
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: Colors.grey[400],
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

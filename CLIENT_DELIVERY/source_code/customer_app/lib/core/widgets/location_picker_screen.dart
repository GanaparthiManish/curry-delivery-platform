import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../location_service.dart';
import '../pro_theme.dart';
import '../location_store.dart';
import 'dart:async';

class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  const LocationPickerScreen({super.key, this.initialPosition});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _pickedLocation;
  String _address = "Searching...";
  bool _isLoading = false;
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pincodeController = TextEditingController();
  
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounce;
  String _selectedTag = "Home";

  @override
  void initState() {
    super.initState();
    _pickedLocation = widget.initialPosition ?? const LatLng(17.4483, 78.3488); // Gachibowli
    _phoneController.text = LocationStore().phone;
    _pincodeController.text = LocationStore().pincode;
    _detailsController.text = LocationStore().houseNumber;
    _fetchAddress(_pickedLocation!);
  }

  Future<void> _fetchAddress(LatLng position) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _address = "Locating...";
    });
    try {
      final addr = await LocationService.getAddressFromLatLng(position.latitude, position.longitude);
      if (mounted) {
        setState(() {
          _address = addr;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _address = "Error fetching address";
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length > 2) {
        final results = await LocationService.searchPlaces(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _searchResults = [];
          });
        }
      }
    });
  }

  void _moveToLocation(double lat, double lng) {
    final pos = LatLng(lat, lng);
    _mapController.move(pos, 16.0);
    if (mounted) {
      setState(() {
        _pickedLocation = pos;
        _searchResults = [];
        _searchController.clear();
      });
    }
    _fetchAddress(pos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Select delivery location", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 1. MAP
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pickedLocation!,
                initialZoom: 16.0,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    _pickedLocation = position.center;
                  }
                },
                onMapEvent: (event) {
                  if (event is MapEventMoveEnd) {
                    _fetchAddress(_pickedLocation!);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.univfoods.curry',
                ),
              ],
            ),
          ),

          // 2. SEARCH BAR (Floating)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: "Search for area, street name...",
                      hintStyle: GoogleFonts.inter(color: Colors.grey[500], fontSize: 15),
                      prefixIcon: const Icon(Icons.search, color: ProTheme.primary, size: 24),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                    ),
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (c, i) => Divider(height: 1, color: Colors.grey[100]),
                      itemBuilder: (context, index) {
                        final res = _searchResults[index];
                        return ListTile(
                          leading: const Icon(Icons.location_on_outlined, size: 20, color: Colors.grey),
                          title: Text(res['display_name'] ?? 'Unknown Location', style: GoogleFonts.inter(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () {
                            if (res['lat'] != null && res['lon'] != null) {
                              _moveToLocation(
                                double.parse(res['lat'].toString()),
                                double.parse(res['lon'].toString()),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 3. CENTER MARKER
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(Icons.location_on, size: 48, color: ProTheme.primary),
              ),
            ),
          ),

          // 4. CURRENT LOCATION BUTTON
          Positioned(
            bottom: 430, // Above the sheet
            right: 16,
            left: 16,
            child: Center(
              child: InkWell(
                onTap: () async {
                  final pos = await LocationService.getCurrentPosition();
                  if (pos != null) {
                    _moveToLocation(pos.latitude, pos.longitude);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
                    border: Border.all(color: Colors.grey[100]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.my_location, color: ProTheme.highlight, size: 18),
                      const SizedBox(width: 8),
                      Text("Use current location", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: ProTheme.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 5. BOTTOM SHEET PANEL
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 420,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 16),
                    
                    Text("Delivery details", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: ProTheme.primary, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _address,
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _detailsController,
                            decoration: InputDecoration(
                              labelText: "House/Flat No.*",
                              labelStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
                              hintText: "E.g. Floor 2, 401",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _pincodeController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: "Pincode*",
                              labelStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
                              hintText: "500032",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: "Phone Number*",
                        labelStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
                        prefixIcon: const Icon(Icons.phone_android, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    Text("Save address as", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    
                    Row(
                      children: [
                        _tagChip("Home", Icons.home_outlined),
                        const SizedBox(width: 12),
                        _tagChip("Work", Icons.work_outline),
                        const SizedBox(width: 12),
                        _tagChip("Other", Icons.location_on_outlined),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : () {
                          if (_detailsController.text.isEmpty || _phoneController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill House No and Phone Number")));
                            return;
                          }
                          Navigator.pop(context, {
                            'address': _address,
                            'lat': _pickedLocation!.latitude,
                            'lng': _pickedLocation!.longitude,
                            'details': _detailsController.text,
                            'pincode': _pincodeController.text,
                            'phone': _phoneController.text,
                            'tag': _selectedTag,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ProTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text("Confirm Location", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(String label, IconData icon) {
    bool isSelected = _selectedTag == label;
    return InkWell(
      onTap: () => setState(() => _selectedTag = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? ProTheme.accent : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? ProTheme.primary : Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? ProTheme.primary : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? ProTheme.primary : Colors.grey[700])),
          ],
        ),
      ),
    );
  }
}

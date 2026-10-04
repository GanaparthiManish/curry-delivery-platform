import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/supabase_config.dart';
import '../../core/cart_state.dart';
import '../../core/pro_theme.dart';
import '../../core/location_store.dart';
import '../../core/address_store.dart';
import '../../core/profile_store.dart';
import '../../core/favorite_store.dart';
import '../../core/widgets/location_picker_screen.dart';
import '../../core/widgets/banner_carousel.dart';
import '../cart/cart_screen.dart';
import '../home/global_search_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  Map<String, dynamic>? _assignedVendor;
  bool _isLoadingVendor = true;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _fetchTrustedVendor();
  }

  Future<void> _fetchTrustedVendor() async {
    final String itemType = (widget.product['item_type'] ?? widget.product['display_type'] ?? 'NORMAL_VENDOR_ITEM').toString().toUpperCase();
    final bool isPopular = itemType == 'POPULAR_ITEM' || itemType == 'POPULAR';
    
    if (!isPopular && widget.product['vendor_id'] != null) {
      try {
        final res = await SupabaseConfig.client.from('vendors').select('*').eq('id', widget.product['vendor_id']).single();
        if (mounted) {
          setState(() {
            _assignedVendor = {
              'id': res['id'],
              'vendor_id': res['id'],
              'vendor_name': res['name'],
              'price': widget.product['price'],
              'rating': res['rating'],
              'prep_time': 30,
            };
            _isLoadingVendor = false;
          });
        }
      } catch (e) {
        debugPrint("Error fetching fixed vendor: $e");
        setState(() => _isLoadingVendor = false);
      }
      return;
    }

    try {
      final loc = LocationStore().selectedLocation;
      if (loc == null) {
        setState(() => _isLoadingVendor = false);
        return;
      }

      final res = await SupabaseConfig.client.rpc('get_trusted_vendor_for_item_v2', params: {
        'p_product_id': widget.product['id'],
        'p_lat': loc.latitude,
        'p_lng': loc.longitude,
      });

      if (mounted && res != null && (res as List).isNotEmpty) {
        setState(() {
          _assignedVendor = Map<String, dynamic>.from(res.first);
          _isLoadingVendor = false;
        });
      } else {
        setState(() => _isLoadingVendor = false);
      }
    } catch (e) {
      debugPrint("Error fetching trusted vendor: $e");
      setState(() => _isLoadingVendor = false);
    }
  }

  void _showChooseVendorModal() async {
    final loc = LocationStore().selectedLocation;
    if (loc == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VendorSelectionModal(
        foodId: widget.product['id'],
        userLat: loc.latitude,
        userLng: loc.longitude,
        onSelected: (vendor) {
          setState(() {
            _assignedVendor = vendor;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = SupabaseConfig.imageUrl(widget.product['image_url'] ?? widget.product['image']);
    final isVeg = widget.product['is_veg'] ?? false;
    final price = _assignedVendor?['price'] ?? widget.product['price'] ?? 0;
    final name = widget.product['name'] ?? "Food Item";
    final desc = widget.product['description'] ?? "Spicy and tasty dish made with fresh ingredients.";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
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
              // Refresh vendor for new location
              _fetchTrustedVendor();
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    "Deliver to ",
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Icon(Icons.location_on, size: 10, color: Color(0xFF2E7D32)),
                ],
              ),
              Row(
                children: [
                  Text(
                    LocationStore().selectedLabel.isNotEmpty ? LocationStore().selectedLabel : "Select Location",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GlobalSearchScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black87),
            onPressed: () async {
              final String name = widget.product['name'] ?? "Food Item";
              final String desc = widget.product['description'] ?? "Spicy and tasty dish made with fresh ingredients.";
              final String msg = "Check out $name on UnivFoods! $desc\nDownload the app to order.";
              // We'll just copy to clipboard since share_plus isn't explicitly imported
              final data = ClipboardData(text: msg);
              await Clipboard.setData(data);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copied to clipboard!")));
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Image Carousel Container
              Container(
                width: double.infinity,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      CachedNetworkImage(
                        imageUrl: img,
                        width: double.infinity,
                        height: 250,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: ValueListenableBuilder<Set<String>>(
                          valueListenable: FavoriteStore.productFavorites,
                          builder: (context, favs, _) {
                            final String prodId = widget.product['id'].toString();
                            final bool isFav = favs.contains(prodId);
                            return GestureDetector(
                              onTap: () {
                                FavoriteStore.toggleProduct(widget.product);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isFav ? Icons.favorite : Icons.favorite_border,
                                  color: isFav ? Colors.red : Colors.black87,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                            const SizedBox(width: 6),
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 6),
                            Container(width: 6, height: 6, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(3))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Text(
                    "₹$price",
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.circle, color: isVeg ? Colors.green : Colors.red, size: 12),
                  const SizedBox(width: 8),
                  Text(
                    "Serves 1",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                desc,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _buildQuickInfo(),
              const SizedBox(height: 24),
              _buildQuantitySelector(),
              const SizedBox(height: 32),
              _buildTrustedVendorSection(),
              const SizedBox(height: 24),
              _buildAddInstructions(),
              const SizedBox(height: 32),
              const BannerCarousel(),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomSheet: _buildBottomAction(),
    );
  }

  Widget _buildCircleButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
        child: Icon(icon, size: 20, color: Colors.black),
      ),
    );
  }

  Widget _buildQuickInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _infoItem("Delivered in", "${_assignedVendor?['prep_time'] ?? 30}-45 mins", Icons.timer_outlined)),
        const SizedBox(width: 8),
        Expanded(child: _infoItem("Rating", "${_assignedVendor?['rating'] ?? 4.3}", Icons.star_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _infoItem("Delivery", "Free > ₹100", Icons.delivery_dining_outlined)),
      ],
    );
  }

  Widget _infoItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text(label, 
            style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: ProTheme.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(value, 
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuantitySelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Quantity", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
        Container(
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              IconButton(onPressed: () => setState(() => _quantity = (_quantity > 1) ? _quantity - 1 : 1), icon: const Icon(Icons.remove)),
              Text("$_quantity", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => setState(() => _quantity++), icon: const Icon(Icons.add)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrustedVendorSection() {
    if (_isLoadingVendor) return const Center(child: CircularProgressIndicator());
    final String itemType = (widget.product['item_type'] ?? widget.product['display_type'] ?? 'NORMAL_VENDOR_ITEM').toString().toUpperCase();
    final bool isPopular = itemType == 'POPULAR_ITEM' || itemType == 'POPULAR';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: !isPopular ? Colors.blue[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: !isPopular ? Colors.blue[100]! : Colors.green[100]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(!isPopular ? Icons.verified : Icons.check_circle, color: !isPopular ? Colors.blue : Colors.green, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _assignedVendor?['vendor_name'] ?? "Trusted Vendor", 
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, 
                        fontSize: 14, 
                        color: !isPopular ? Colors.blue[900] : Colors.green[900]
                      )
                    ),
                    const SizedBox(height: 4),
                    Text(
                      !isPopular
                        ? "This item is exclusively served by this vendor and cannot be mixed with other vendors in the same order."
                        : "Recommended Vendor: ${_assignedVendor?['vendor_name'] ?? 'Finding best...'} • ${_assignedVendor?['rating'] ?? '4.2'} ⭐", 
                      style: GoogleFonts.inter(fontSize: 12, color: !isPopular ? Colors.blue[700] : Colors.green[700])
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPopular && false) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: _showChooseVendorModal,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue[200]!)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Choose vendor (optional)", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue[800])),
                          Text(_assignedVendor != null ? "Selected: ${_assignedVendor!['vendor_name']}" : "Select a specific vendor if you have a preference", 
                               style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.blue),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddInstructions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Add instructions (optional)", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: "E.g. Less spicy, No onions, Extra chutney...",
            hintStyle: GoogleFonts.inter(color: Colors.grey[400], fontSize: 14),
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))]),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CartScreen(isTab: false)),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("₹${(_assignedVendor?['price'] ?? widget.product['price'] ?? 0) * _quantity}", style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold)),
                Text("View Bill", style: GoogleFonts.inter(fontSize: 12, color: ProTheme.primary, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                _checkAndPromptAddressFlow(() {
                  if (_assignedVendor == null) {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Finding best vendor... please wait")));
                     _fetchTrustedVendor();
                     return;
                  }
                  try {
                    for (int i = 0; i < _quantity; i++) {
                      GlobalCart().addItem(widget.product, _assignedVendor!);
                    }
                    // 🛒 NAVIGATE TO CART AFTER ADDING
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => CartScreen(isTab: false)),
                    );
                  } catch (e) {
                    if (e.toString().contains("VLOCK_ERR")) {
                      _showClearCartDialog();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ProTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text("Add to Cart", style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCartDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Clear Cart?", style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text("Your cart contains items from a different vendor. Clear cart to add items from ${_assignedVendor?['vendor_name'] ?? 'this vendor'}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              GlobalCart().clear();
              Navigator.pop(context);
              // Retry adding
              for (int i = 0; i < _quantity; i++) {
                GlobalCart().addItem(widget.product, _assignedVendor!);
              }
              Navigator.pop(context);
            }, 
            child: const Text("Clear & Add", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }

  void _checkAndPromptAddressFlow(VoidCallback onConfirmed) async {
    final store = LocationStore();

    if (store.selectedAddress == "Finding location..." ||
        store.selectedAddress == "Select your location" ||
        store.selectedLocation == null) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
      );
      if (result != null) {
        await LocationStore().updateLocation(
          LatLng(result['lat'], result['lng']),
          result['address'],
          result['tag'],
          house: result['details'] ?? '',
          pincode: result['pincode'] ?? '',
          phone: result['phone'] ?? '',
        );

        final uid = SupabaseConfig.currentUid;
        if (uid != null) {
          try {
            await AddressStore().saveAddress({
              'label': result['tag'] ?? 'Address',
              'address_line': result['address'] ?? '',
              'house_number': result['details'] ?? '',
              'pincode': result['pincode'] ?? '',
              'phone': result['phone'] ?? '',
              'latitude': result['lat'],
              'longitude': result['lng'],
            });
          } catch (e) {
            debugPrint("Error saving address: $e");
          }
        }

        await _fetchTrustedVendor();

        if (store.phone.isNotEmpty &&
            store.houseNumber.isNotEmpty &&
            store.pincode.isNotEmpty) {
          onConfirmed();
        } else {
          _showAddressDetailsDialog(
            lat: store.selectedLocation?.latitude ?? 0.0,
            lng: store.selectedLocation?.longitude ?? 0.0,
            address: store.selectedAddress,
            pincode: store.pincode,
            onConfirmed: onConfirmed,
          );
        }
      }
      return;
    }

    if (store.phone.isEmpty || store.houseNumber.isEmpty || store.pincode.isEmpty) {
      _showAddressDetailsDialog(
        lat: store.selectedLocation?.latitude ?? 0.0,
        lng: store.selectedLocation?.longitude ?? 0.0,
        address: store.selectedAddress,
        pincode: store.pincode,
        onConfirmed: onConfirmed,
      );
      return;
    }

    onConfirmed();
  }

  void _showAddressDetailsDialog({
    String label = 'Current Location',
    required double lat,
    required double lng,
    required String address,
    required String pincode,
    required VoidCallback onConfirmed,
  }) {
    final store = LocationStore();
    final houseCtrl = TextEditingController(text: store.houseNumber);
    final pinCtrl = TextEditingController(text: pincode.isNotEmpty ? pincode : store.pincode);
    final phoneCtrl = TextEditingController(
      text: store.phone.isNotEmpty
          ? store.phone
          : (ProfileStore().profile?['phone'] ?? ''),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivery Details',
                style: GoogleFonts.outfit(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(address,
                style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextField(
                controller: houseCtrl,
                decoration: const InputDecoration(labelText: "House/Flat No.")),
            TextField(
                controller: pinCtrl,
                decoration: const InputDecoration(labelText: "Pincode"),
                keyboardType: TextInputType.number),
            TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: "Phone Number"),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (houseCtrl.text.isEmpty ||
                      pinCtrl.text.isEmpty ||
                      phoneCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Please fill all address details"),
                          backgroundColor: Colors.red),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  await _setAddress(label, address,
                      house: houseCtrl.text,
                      pin: pinCtrl.text,
                      phone: phoneCtrl.text,
                      lat: lat,
                      lng: lng);
                  onConfirmed();
                },
                child: const Text("Confirm Location"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAddress(String label, String addr,
      {String house = '',
      String pin = '',
      String phone = '',
      double? lat,
      double? lng}) async {
    if (lat != null && lng != null) {
      await LocationStore().updateLocation(LatLng(lat, lng), addr, label,
          house: house, pincode: pin, phone: phone);
      final uid = SupabaseConfig.currentUid;
      if (uid != null) {
        await AddressStore().saveAddress({
          'label': label,
          'address_line': addr,
          'house_number': house,
          'pincode': pin,
          'phone': phone,
          'latitude': lat,
          'longitude': lng,
        });
      }
    }
  }
}

class _VendorSelectionModal extends StatelessWidget {
  final String foodId;
  final double userLat;
  final double userLng;
  final Function(Map<String, dynamic>) onSelected;

  const _VendorSelectionModal({required this.foodId, required this.userLat, required this.userLng, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, size: 24)),
                const SizedBox(width: 16),
                Text("Choose Vendor", style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: SupabaseConfig.client.rpc('get_all_vendors_for_item', params: {
                'p_product_id': foodId,
                'p_lat': userLat,
                'p_lng': userLng,
              }),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final vendors = snapshot.data as List;
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildAutoAssignOption(),
                    const SizedBox(height: 24),
                    Text("Select a Specific Vendor", style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey[800])),
                    const SizedBox(height: 16),
                    ...vendors.map((v) => _buildVendorTile(Map<String, dynamic>.from(v))),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoAssignOption() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.radio_button_checked, color: Color(0xFF2E7D32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("Nearest Vendor", style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(4)),
                      child: Text("FASTEST", style: GoogleFonts.inter(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text("We'll choose the best and nearest vendor for you.", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorTile(Map<String, dynamic> v) {
    final price = v['price'];
    final distance = (v['distance'] as num?)?.toDouble() ?? 0.0;
    
    return InkWell(
      onTap: () {
        onSelected({
          'id': v['vendor_id'],
          'vendor_id': v['vendor_id'],
          'vendor_name': v['vendor_name'],
          'price': v['price'],
          'rating': v['rating'],
          'prep_time': 30,
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(imageUrl: SupabaseConfig.imageUrl(v['image_url']), width: 56, height: 56, fit: BoxFit.cover),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['vendor_name'] ?? 'Vendor', style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Color(0xFFFFB300), size: 14),
                      Text(" ${v['rating']}", style: GoogleFonts.inter(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text("•", style: TextStyle(color: Colors.grey[400])),
                      const SizedBox(width: 8),
                      Text("${distance.toStringAsFixed(1)} km", style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("₹$price", style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black87)),
                const SizedBox(height: 4),
                const Icon(Icons.radio_button_off, color: Colors.grey, size: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

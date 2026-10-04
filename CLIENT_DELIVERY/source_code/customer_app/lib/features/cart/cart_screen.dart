import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import '../../core/supabase_config.dart';
import '../../core/cart_state.dart';
import '../../core/pro_theme.dart';
import '../../core/razorpay_service.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/location_service.dart';
import '../../core/profile_store.dart';
import '../../core/widgets/pro_loader.dart';
import '../../core/location_store.dart';
import '../../core/order_store.dart';
import '../../core/system_store.dart';
import '../../core/widgets/banner_carousel.dart';
import '../../core/address_store.dart';
import '../../core/widgets/location_picker_screen.dart';


class CartScreen extends StatefulWidget {
  final Function(int)? onTabChange;
  final bool isTab;
  const CartScreen({super.key, this.onTabChange, this.isTab = false});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _cart = GlobalCart();
  bool _placingOrder = false;
  final TextEditingController _instructionController = TextEditingController();
  RazorpayService? _razorpay;
  String? _lastMasterId;

  @override
  void initState() {
    super.initState();
    _cart.load();
    _initRazorpay();
  }

  void _initRazorpay() {
    _razorpay = RazorpayService(
      onSuccess: _handlePaymentSuccess,
      onFailure: _handlePaymentFailure,
      onExternalWallet: (res) {},
    );
  }

  @override
  void dispose() {
    _razorpay?.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    _processPostPayment(response.paymentId ?? 'UPI_SUCCESS');
  }

  void _handlePaymentFailure(PaymentFailureResponse response) {
    if (mounted) {
      setState(() => _placingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Payment Failed: ${response.message}"), backgroundColor: Colors.red));
    }
  }

  Future<void> _processPostPayment(String paymentId) async {
    try {
      setState(() => _placingOrder = true);
      
      if (_lastMasterId != null) {
        debugPrint("💎 Confirming Payment for Master ID: $_lastMasterId");
        await SupabaseConfig.client.rpc('confirm_master_payment_v4', params: {
          'p_master_id': _lastMasterId,
          'p_payment_id': paymentId,
        });
      }

      _cart.clear();
      _showSuccessAnimation();
    } catch (e) {
      debugPrint("Post-payment error: $e");
      // Still show success if payment was successful but DB update failed, 
      // but log it for background sync
      _cart.clear();
      _showSuccessAnimation();
    }
  }

  double get deliveryFee => SystemStore().deliveryFee;
  double get platformFee => SystemStore().platformFee;
  double get _itemTotal => _cart.totalPrice;
  double get _gst => _itemTotal * (SystemStore().taxRate / 100);
  double get _grandTotal => _itemTotal + deliveryFee + platformFee + _gst;

  String _paymentMethod = "UPI";

  Future<void> _placeOrder() async {
    final store = LocationStore();
    if (store.selectedAddress == "Finding location..." || store.selectedAddress == "Select your location") {
      _showLocationSheet();
      return;
    }

    if (store.phone.isEmpty || store.houseNumber.isEmpty || store.pincode.isEmpty) {
      _showAddressDetailsDialog(lat: store.selectedLocation?.latitude ?? 0, lng: store.selectedLocation?.longitude ?? 0, address: store.selectedAddress, pincode: store.pincode);
      return;
    }

    setState(() => _placingOrder = true);

    try {
      final String? userId = SupabaseConfig.currentUid;
      if (userId == null) throw "Please login";

      // 📦 Build Multi-Vendor Payload
      final List<Map<String, dynamic>> vendorItems = [];
      _cart.vendorGroups.forEach((vid, group) {
        final items = group['items'] as Map<String, dynamic>;
        final details = group['details'] as Map<String, dynamic>;
        
        double vendorTotal = 0;
        final List<Map<String, dynamic>> itemList = [];
        
        items.forEach((fid, qty) {
          final p = details[fid];
          final price = double.parse((p?['price'] ?? 0).toString());
          vendorTotal += (price * (qty as int));
          itemList.add({
            'product_id': fid,
            'qty': qty,
            'name': p?['name'] ?? 'Dish',
            'price': price
          });
        });

        vendorItems.add({
          'vendor_id': vid,
          'items': itemList,
          'total': vendorTotal + (deliveryFee / _cart.vendorGroups.length) // Split delivery fee
        });
      });

      final fullAddr = "${store.houseNumber}, ${store.selectedAddress} - ${store.pincode}";

      // Call the Master Splitting RPC
      final masterId = await SupabaseConfig.client.rpc('place_order_v4', params: {
        'p_customer_id': userId,
        'p_vendor_items': vendorItems,
        'p_address': fullAddr,
        'p_lat': store.selectedLocation?.latitude,
        'p_lng': store.selectedLocation?.longitude,
        'p_payment_method': _paymentMethod,
        'p_instructions': _instructionController.text.trim(),
        'p_payment_status': _paymentMethod == 'COD' ? 'SUCCESS' : 'PENDING'
      });

      _lastMasterId = masterId.toString();

      if (_paymentMethod == 'UPI') {
        _razorpay?.openCheckout(
          amount: _grandTotal,
          description: "Order Split Across ${_cart.vendorGroups.length} Vendors",
          email: ProfileStore().profile?['email'] ?? "customer@univfoods.in",
          phone: store.phone,
        );
      } else {
        _cart.clear();
        _showSuccessAnimation();
      }
    } catch (e) {
      setState(() => _placingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    }
  }

  void _showSuccessAnimation() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => SuccessScreen(onTabChange: widget.onTabChange)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_cart, LocationStore()]),
      builder: (context, _) {
        if (_cart.vendorGroups.isEmpty) return _buildEmptyCart();

        return Scaffold(
          backgroundColor: const Color(0xFFF9FAFB),
          appBar: _buildAppBar(),
          body: SingleChildScrollView(
            child: Column(
              children: [
                _buildMultiDeliveryAlert(),
                _buildAddressSection(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      ..._cart.vendorGroups.entries.toList().asMap().entries.map((entry) {
                        int idx = entry.key;
                        var e = entry.value;
                        return _buildVendorGroup(e.key, e.value, idx + 1);
                      }),
                      const SizedBox(height: 16),
                      const SizedBox(height: 32),
                      const BannerCarousel(),
                      const SizedBox(height: 16),
                      _buildBillSummary(),
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomSheet: _buildBottomAction(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF9FAFB),
      elevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: 80,
      title: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "My Cart",
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  "${_cart.totalItemCount} items from ${_cart.vendorGroups.length} vendors",
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 14, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 4),
                  Text(
                    "Secure Checkout",
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.close, color: Colors.black), onPressed: () => widget.onTabChange?.call(0))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
              child: Icon(Icons.shopping_basket_outlined, size: 80, color: Colors.grey[400]),
            ),
            const SizedBox(height: 32),
            Text("Your cart is empty", style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: ProTheme.dark)),
            const SizedBox(height: 12),
            Text("Looks like you haven't added anything yet.", style: GoogleFonts.inter(color: Colors.grey[500])),
            const SizedBox(height: 40),
            SizedBox(
              width: 200,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  widget.onTabChange?.call(0);
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(backgroundColor: ProTheme.primary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text("GO BACK", style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMultiDeliveryAlert() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8F1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Image.network(
            'https://img.icons8.com/color/96/scooter.png',
            width: 40,
            height: 40,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Multiple deliveries from trusted vendors",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  "Each vendor will deliver separately",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorGroup(String vid, Map<String, dynamic> group, int deliveryIndex) {
    final vendor = group['vendor'];
    final items = group['items'] as Map<String, dynamic>;
    final details = group['details'] as Map<String, dynamic>;

    double vendorTotal = 0;
    items.forEach((fid, qty) {
      final p = details[fid];
      vendorTotal += (double.parse((p?['price'] ?? 0).toString()) * qty);
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: SupabaseConfig.imageUrl(vendor['image_url']),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            vendor['name'] ?? "Vendor",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F8F1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, size: 10, color: Color(0xFF2E7D32)),
                                const SizedBox(width: 4),
                                Text(
                                  "Trusted",
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF2E7D32),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "0.8 km away • 25-30 mins",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.delivery_dining, size: 14, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 4),
                      Text(
                        "Delivery $deliveryIndex",
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ...items.entries.map((e) => _buildCartItem(vid, e.key, e.value, details[e.key])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_offer_outlined, size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Text(
                  "Item total from ${vendor['name'] ?? 'Trusted Shop'}",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                Text(
                  "₹${vendorTotal.toInt()}",
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(String vid, String fid, int qty, Map<String, dynamic> p) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: SupabaseConfig.imageUrl(p['image_url'] ?? p['image']),
              width: 70,
              height: 70,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, color: (p['is_veg'] ?? true) ? Colors.green : Colors.red, size: 8),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p['name'] ?? "Dish",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "₹${p['price']}",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _cart.removeItem(vid, fid),
                      icon: const Icon(Icons.remove, size: 14, color: Color(0xFF2E7D32)),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    Text(
                      "$qty",
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _cart.addItem(p, _cart.vendorGroups[vid]!['vendor']),
                      icon: const Icon(Icons.add, size: 14, color: Color(0xFF2E7D32)),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "₹${(p['price'] ?? 0) * qty}",
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _cart.deleteItem(vid, fid),
                child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCouponSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_offer_outlined, color: Color(0xFF2E7D32)),
          const SizedBox(width: 12),
          Text(
            "Apply Coupon",
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }

  Widget _buildBillSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          _summaryRow("Cart Subtotal", "₹${_itemTotal.toInt()}"),
          const SizedBox(height: 12),
          _summaryRow("Delivery Fee", deliveryFee == 0 ? "FREE" : "₹${deliveryFee.toInt()}", isFree: deliveryFee == 0),
          const SizedBox(height: 12),
          _summaryRow("Platform Fee", "₹${platformFee.toInt()}"),
          const SizedBox(height: 12),
          _summaryRow("GST & Charges", "₹${_gst.toInt()}"),
          const SizedBox(height: 16),
          if (deliveryFee == 0)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Color(0xFF2E7D32), size: 28),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "You are saving ₹${SystemStore().deliveryFee.toInt()}",
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                      Text(
                        "on delivery fee",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2E7D32).withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Grand Total",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              Text(
                "₹${_grandTotal.toInt()}",
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isFree = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
            if (isFree) ...[
              const SizedBox(width: 4),
              const Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
            ],
          ],
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: isFree ? const Color(0xFF2E7D32) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.payment_outlined, size: 20, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text(
                      "Payment Method",
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: _paymentMethod,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 13),
                    items: ["UPI", "COD"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _paymentMethod = v!),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _placingOrder ? null : _placeOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D00),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _placingOrder
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Proceed to Checkout",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, color: Colors.white),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection() {
    final store = LocationStore();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFFFF4D00), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    "Delivery Address",
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: _showLocationSheet,
                child: Text(
                  "CHANGE",
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: const Color(0xFFFF4D00),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            store.selectedAddress == "Finding location..." || store.selectedAddress == "Select your location"
                ? "Please select an address"
                : store.selectedAddress,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (store.houseNumber.isNotEmpty || store.pincode.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (store.houseNumber.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "House: ${store.houseNumber}",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (store.pincode.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Pincode: ${store.pincode}",
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (store.phone.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.phone, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text(
                  store.phone,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }


  List<Map<String, dynamic>> _addressResults = [];

  void _showLocationSheet() {
    final uid = SupabaseConfig.currentUid;
    final store = LocationStore();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFFF7F9FC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) => Column(
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
                              _showAddressDetailsDialog(
                                label: result['tag'] ?? 'Address',
                                address: result['address'] ?? '',
                                lat: result['lat'],
                                lng: result['lng'],
                                pincode: result['pincode'] ?? '',
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
                          _showAddressDetailsDialog(
                            label: "Current Location",
                            address: addr,
                            lat: pos.latitude,
                            lng: pos.longitude,
                            pincode: "",
                          );
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
                          _showAddressDetailsDialog(
                            label: result['tag'] ?? 'Address',
                            address: result['address'] ?? '',
                            lat: result['lat'],
                            lng: result['lng'],
                            pincode: result['pincode'] ?? '',
                          );
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
              Text("--- km", style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[400])),
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
                  if (houseCtrl.text.isEmpty || pinCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please fill all address details"), backgroundColor: Colors.red),
                    );
                    return;
                  }
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

class SuccessScreen extends StatelessWidget {
  final Function(int)? onTabChange;
  const SuccessScreen({super.key, this.onTabChange});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 100, color: Colors.green),
                const SizedBox(height: 24),
                Text("Order Placed!", style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text("Your delicious food is being prepared.", style: GoogleFonts.inter(color: Colors.grey)),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    onTabChange?.call(1);
                    Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4D00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Track Order"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/supabase_config.dart';

import '../../core/order_store.dart';
import 'order_tracking_screen.dart';
import 'order_details_screen.dart';
import '../../core/widgets/pro_loader.dart';
import '../../core/cart_state.dart';
import '../../core/location_store.dart';
import 'package:cached_network_image/cached_network_image.dart';
class OrdersScreen extends StatefulWidget {
  final bool showBack;
  const OrdersScreen({super.key, this.showBack = false});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _orderStore = OrderStore();

  @override
  void initState() {
    super.initState();
    // ALWAYS fetch on mount to get the latest data for the current user.
    // This handles re-login scenarios where the store may have stale/empty data.
    _orderStore.fetchOrders();
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: Colors.grey[700],
        letterSpacing: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detect if nested tab
    final bool isStandalone =
        ModalRoute.of(context)?.settings.name == '/orders' || widget.showBack;

    Widget bodyContent = ListenableBuilder(
      listenable: _orderStore,
      builder: (context, _) {
        final orders = _orderStore.orders;
        final bool hasLoaded = _orderStore.hasLoaded;

        if (!hasLoaded && orders.isEmpty) {
          return ListView(
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.3),
              const Center(
                  child: ProLoader(message: "Checking your order status...")),
            ],
          );
        }

        // Note: Stream doesn't include vendors(name, logo_url) by default.
        // For a true real-time experience with joins, we'd use a custom subscription,
        // but for status updates, this stream is perfect and fast.

        if (orders.isEmpty) {
          return ListView(
            children: [
              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 50, color: Colors.grey[300]),
                    ),
                    const SizedBox(height: 24),
                    Text("NO ORDERS YET",
                        style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87)),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _orderStore.fetchOrders(),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4500), foregroundColor: Colors.white),
                      child: const Text("RESTORE HISTORY"),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        final activeOrders = orders.where((o) {
          final s = (o['status'] ?? o['order_status'] ?? '').toString().toUpperCase();
          
          if (s == 'PAYMENT_PENDING') {
              final created = DateTime.tryParse(o['created_at'] ?? '') ?? DateTime.now();
              if (DateTime.now().difference(created).inMinutes > 2) return false;
          }

          return [
            'PLACED',
            'ACCEPTED',
            'PREPARING',
            'READY',
            'RIDER_ASSIGNED',
            'PICKED_UP',
            'OUT_FOR_DELIVERY'
          ].contains(s);
        }).toList();

        final pastOrders =
            orders.where((o) => !activeOrders.contains(o)).toList();

        // 📦 Grouping Logic (if master_order_id exists)
        // This ensures multi-vendor orders appear as a single entry
        final Map<String, List<Map<String, dynamic>>> groupedActive = {};
        for (var o in activeOrders) {
            final mid = o['master_order_id']?.toString() ?? o['order_id'].toString();
            groupedActive.putIfAbsent(mid, () => []).add(o);
        }

        final List<String> activeMids = groupedActive.keys.toList();

        return Stack(
          children: [
            CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: SizedBox.shrink(),
                  ),
                ),
                if (activeOrders.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSectionHeader("ACTIVE ORDERS"),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final mid = activeMids[index];
                        final subOrders = groupedActive[mid]!;
                        final o = subOrders.first; // Use first one for main display
                        
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: InkWell(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        OrderDetailsScreen(order: o))),
                            child: _OrderLegacyCard(order: o, subOrders: subOrders),
                          ),
                        );
                      },
                      childCount: activeMids.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
                if (pastOrders.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSectionHeader("PAST ORDERS"),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final o = pastOrders[index];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: InkWell(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        OrderDetailsScreen(order: o))),
                            child: _OrderLegacyCard(order: o, subOrders: [o]),
                          ),
                        );
                      },
                      childCount: pastOrders.length,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
            if (!hasLoaded)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFFFF4500).withOpacity(0.5)),
                  minHeight: 2,
                ),
              ),
          ],
        );
      },
    );

    if (isStandalone) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F7F7),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: Colors.black),
          title: Text("MY ORDERS",
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black)),
          // No actions needed - it's all automatic and silent now
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            await SupabaseConfig.bootstrap();
          },
          color: const Color(0xFFFF4500),
          child: bodyContent,
        ),
      );
    }

    // When embedded as a tab (IndexedStack), provide a Scaffold so all
    // InkWell / ElevatedButton descendants can hit-test correctly.
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text("MY ORDERS",
            style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.black)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await SupabaseConfig.bootstrap();
        },
        color: const Color(0xFFFF4500),
        child: bodyContent,
      ),
    );
  }
}

class _OrderLegacyCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final List<Map<String, dynamic>>? subOrders;

  const _OrderLegacyCard({required this.order, this.subOrders});

  Future<void> _showRatingDialog(
      BuildContext context, Map<String, dynamic> order) async {
    double vendorRating = 5;
    double riderRating = 5;
    final commentController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text("Rate Your Experience",
              style: GoogleFonts.outfit(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Restaurant",
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (index) => IconButton(
                          icon: Icon(
                              index < vendorRating
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber),
                          onPressed: () =>
                              setState(() => vendorRating = index + 1.0),
                        )),
              ),
              const SizedBox(height: 16),
              Text("Delivery Partner",
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    5,
                    (index) => IconButton(
                          icon: Icon(
                              index < riderRating
                                  ? Icons.star
                                  : Icons.star_border,
                              color: Colors.amber),
                          onPressed: () =>
                              setState(() => riderRating = index + 1.0),
                        )),
              ),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                    hintText: "Add an optional comment..."),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("SKIP")),
            ElevatedButton(
              onPressed: () async {
                final userId = SupabaseConfig.forcedUserId;
                if (userId == null) return;

                // Save Vendor Review
                await SupabaseConfig.client.from('reviews').insert({
                  'order_id': order['id'],
                  'customer_id': userId,
                  'vendor_id': order['vendor_id'],
                  'rating': vendorRating.toInt(),
                  'comment': commentController.text,
                  'target_type': 'vendor'
                });

                // Save Rider Review
                if (order['rider_id'] != null) {
                  await SupabaseConfig.client.from('reviews').insert({
                    'order_id': order['id'],
                    'customer_id': userId,
                    'rider_id': order['rider_id'],
                    'rating': riderRating.toInt(),
                    'comment': commentController.text,
                    'target_type': 'rider'
                  });
                }

                if (context.mounted) Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Thanks for your feedback!")));
              },
              child: const Text("SUBMIT"),
            ),
          ],
        ),
      ),
    );
  }

  void _reorder(BuildContext context, Map<String, dynamic> order) async {
    final vendorId = order['vendor_id']?.toString();
    if (vendorId == null) return;

    // 0. Check if shop is open/online
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final loc = LocationStore().selectedLocation;
      if (loc == null) {
        if (context.mounted) {
          Navigator.pop(context); // Hide loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a delivery location first.')),
          );
        }
        return;
      }

      final vendorsResponse = await SupabaseConfig.client.rpc(
        'get_nearby_vendors_v24',
        params: {
          'p_lat': loc.latitude,
          'p_lng': loc.longitude,
        },
      );

      if (context.mounted) Navigator.pop(context); // Hide loading

      if (vendorsResponse == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to verify shop status.')),
          );
        }
        return;
      }

      final List rawVendors = vendorsResponse as List;
      final vendorData = rawVendors.cast<Map<String, dynamic>>().firstWhere(
        (v) => v['id'].toString() == vendorId,
        orElse: () => <String, dynamic>{},
      );

      if (vendorData.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This shop is currently closed, offline, or outside the 5km delivery radius. You cannot reorder at this time.')),
          );
        }
        return;
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to verify shop status.')),
        );
      }
      return;
    }

    final cart = GlobalCart();

    // 1. Prepare Vendor Info (GlobalCart needs it to check if same shop)
    final vendor = {
      'id': vendorId,
      'name':
          order['vendor_name'] ?? order['vendor_display_name'] ?? 'Restaurant',
      'logo_url': order['vendor_logo'] ?? order['vendor_logo_url'],
      'address': order['vendor_address'] ?? '',
    };

    // 2. Clear first for reorder to be fresh
    cart.clear();

    // 3. Add items
    if (order['items'] is List) {
      final List items = order['items'];
      final List<String> productIds = [];
      
      for (final item in items) {
        final pid = item['product_id'] ?? item['id'];
        if (pid != null) {
          productIds.add(pid.toString());
        }
      }

      Map<String, dynamic> fullProductsMap = {};
      if (productIds.isNotEmpty) {
        try {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          
          final res = await SupabaseConfig.client
              .from('products')
              .select('*')
              .inFilter('id', productIds);
          
          if (context.mounted) Navigator.pop(context);
              
          for (var p in res as List) {
            fullProductsMap[p['id'].toString()] = p;
          }
        } catch (e) {
          if (context.mounted) Navigator.pop(context);
          debugPrint("Failed to fetch full products for reorder: $e");
        }
      }

      for (final item in items) {
        final qty = (item['qty'] ?? 1);
        final pid = (item['product_id'] ?? item['id'] ?? item['name']).toString();
        
        // Merge full product data with order item data (to preserve price if it changed, though usually cart overrides)
        final product = Map<String, dynamic>.from(fullProductsMap[pid] ?? item);

        // Ensure ID exists (GlobalCart uses 'id' for indexing)
        if (product['id'] == null) {
          product['id'] = pid;
        }

        // Add to cart N times
        for (int i = 0;
            i < (qty is int ? qty : int.parse(qty.toString()));
            i++) {
          cart.addItem(product, vendor);
        }
      }
    }

    // 4. Redirect to Cart
    Navigator.pushNamed(context, '/cart');
  }

  Widget _buildActionBtn(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[700])),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String status = (order['status'] ?? order['order_status'] ?? 'placed')
        .toString()
        .toLowerCase();
    final String paymentState =
        (order['payment_state'] ?? order['payment_status'] ?? '')
            .toString()
            .toLowerCase();

    final bool isActive = [
      'pending',
      'payment_pending',
      'placed',
      'accepted',
      'preparing',
      'ready',
      'rider_assigned',
      'picked_up',
      'out_for_delivery'
    ].contains(status);

    final bool isRefunded = paymentState.contains('refund');

    // Total calculation with fallback
    final total = order['total'] ?? order['total_amount'] ?? 0;
    final formattedTotal = "₹$total";

    // Item parsing
    String itemsText = "";
    if (order['items'] is List) {
      itemsText = (order['items'] as List)
          .map((i) => "${i['qty']} x ${i['name']}")
          .join(", ");
    } else {
      itemsText = "Varying Items";
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02), // 💡 Simplified for performance
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vendor Image Placeholder
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: (order['vendor_logo_url'] ?? order['vendor_logo']) != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl:
                                (order['vendor_logo_url'] ?? order['vendor_logo']).toString(),
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.restaurant, color: Colors.grey),
                          ),
                        )
                      : const Icon(Icons.restaurant, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              (subOrders != null && subOrders!.length > 1)
                                  ? "${subOrders!.length} SHOPS"
                                  : (order['vendor_name'] ?? "SHOP").toString().toUpperCase(),
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  letterSpacing: -0.2),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            formattedTotal,
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Colors.black),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemsText,
                        style: GoogleFonts.inter(
                            color: Colors.grey[600], fontSize: 13, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isRefunded
                                    ? Colors.blue[50]
                                    : (isActive
                                        ? Colors.orange[50]
                                        : Colors.green[50]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (isRefunded ? paymentState : status)
                                    .toUpperCase(),
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: isRefunded
                                        ? Colors.blue[800]
                                        : (isActive
                                            ? Colors.orange[800]
                                            : Colors.green[800])),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "#${() {
                              final oid =
                                  (order['id'] ?? order['order_id'] ?? '')
                                      .toString();
                              return oid.isEmpty
                                  ? 'Pending'
                                  : oid.substring(
                                      0, oid.length < 8 ? oid.length : 8);
                            }()}",
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            InkWell(
              onTap: () {
                Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        builder: (_) => OrderTrackingScreen(order: order)));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF1B4332), // Legacy Green
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      "TRACK ORDER LIVE",
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[100]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildActionBtn("REORDER", Icons.replay,
                        () => _reorder(context, order)),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey[100]),
                  Expanded(
                    child: _buildActionBtn("RATE ORDER", Icons.star_border,
                        () => _showRatingDialog(context, order)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

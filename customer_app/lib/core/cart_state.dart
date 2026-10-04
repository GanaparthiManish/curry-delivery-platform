import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class GlobalCart extends ChangeNotifier {
  static final GlobalCart _instance = GlobalCart._internal();
  factory GlobalCart() => _instance;
  GlobalCart._internal();

  // Multi-Vendor Architecture
  // Structure: { vendor_id: { "vendor": vendor_obj, "items": { food_id: qty }, "details": { food_id: food_obj } } }
  final Map<String, Map<String, dynamic>> _vendorGroups = {};
  
  UUID? lockedVendorId; // For fixed-vendor items

  bool _isLoaded = false;
  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? data = prefs.getString('univ_cart_v2');
      if (data != null) {
        final Map<String, dynamic> decoded = jsonDecode(data);
        _vendorGroups.clear();
        decoded.forEach((vid, group) {
          _vendorGroups[vid] = Map<String, dynamic>.from(group);
        });
      }
      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading cart: $e");
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('univ_cart_v2', jsonEncode(_vendorGroups));
    } catch (e) {
      debugPrint("Error saving cart: $e");
    }
  }

  void addItem(Map<String, dynamic> product, Map<String, dynamic> vendor) {
    final String vid = vendor['id'].toString();
    final String fid = product['id'].toString();
    // Normalize item type: POPULAR_ITEM or NORMAL_VENDOR_ITEM
    final String itemType = (product['item_type'] ?? product['display_type'] ?? 'NORMAL_VENDOR_ITEM').toString().toUpperCase();
    final bool isPopular = itemType == 'POPULAR_ITEM' || itemType == 'POPULAR';
    final bool isNormal = !isPopular;

    // 1. Locked Vendor Logic (for Normal Vendor Items)
    // Rule: User CANNOT add another normal vendor’s item if cart is locked to a normal vendor.
    if (isNormal) {
      if (lockedVendorId != null && lockedVendorId != vid) {
        throw Exception("VLOCK_ERR: Cannot order from multiple vendors in one order.");
      }
      
      // Check if any other NORMAL item exists in cart from a different vendor
      bool hasOtherNormalVendor = false;
      _vendorGroups.forEach((vId, group) {
        if (vId != vid) {
          final details = group["details"] as Map<String, dynamic>;
          details.forEach((fId, p) {
            final pType = (p['item_type'] ?? p['display_type'] ?? 'NORMAL_VENDOR_ITEM').toString().toUpperCase();
            if (pType != 'POPULAR_ITEM' && pType != 'POPULAR') {
              hasOtherNormalVendor = true;
            }
          });
        }
      });

      if (hasOtherNormalVendor) {
        throw Exception("VLOCK_ERR: Cannot order from multiple vendors in one order.");
      }

      // Lock to this vendor if it's the first normal item
      lockedVendorId = vid;
    }

    // 2. Popular Item Exception: Even if cart locked to normal vendor, user CAN still add Popular Items.
    // (This is implicitly handled by not throwing VLOCK_ERR for popular items)

    if (!_vendorGroups.containsKey(vid)) {
      _vendorGroups[vid] = {
        "vendor": vendor,
        "items": <String, int>{},
        "details": <String, dynamic>{}
      };
    }

    final group = _vendorGroups[vid]!;
    final items = group["items"] as Map<String, dynamic>;
    final details = group["details"] as Map<String, dynamic>;

    items[fid] = (items[fid] ?? 0) + 1;
    details[fid] = product;

    _save();
    notifyListeners();
  }

  void removeItem(String vid, String fid) {
    if (!_vendorGroups.containsKey(vid)) return;

    final group = _vendorGroups[vid]!;
    final items = group["items"] as Map<String, dynamic>;
    final details = group["details"] as Map<String, dynamic>;

    if (items[fid] != null && items[fid] > 1) {
      items[fid] = items[fid] - 1;
    } else {
      items.remove(fid);
      details.remove(fid);
    }

    if (items.isEmpty) {
      _vendorGroups.remove(vid);
    }

    _save();
    notifyListeners();
  }

  void deleteItem(String vid, String fid) {
    if (!_vendorGroups.containsKey(vid)) return;

    final group = _vendorGroups[vid]!;
    final items = group["items"] as Map<String, dynamic>;
    final details = group["details"] as Map<String, dynamic>;

    items.remove(fid);
    details.remove(fid);

    if (items.isEmpty) {
      _vendorGroups.remove(vid);
    }
    
    // If no more items, unlock vendor
    if (_vendorGroups.isEmpty) {
      lockedVendorId = null;
    }

    _save();
    notifyListeners();
  }

  void clear() {
    _vendorGroups.clear();
    lockedVendorId = null;
    _save();
    notifyListeners();
  }

  double get totalPrice {
    double total = 0;
    _vendorGroups.forEach((vid, group) {
      final items = group["items"] as Map<String, dynamic>;
      final details = group["details"] as Map<String, dynamic>;
      items.forEach((fid, qty) {
        final p = details[fid];
        final price = p?['price'] ?? 0;
        total += (double.parse(price.toString()) * qty);
      });
    });
    return total;
  }

  int get totalItemCount {
    int count = 0;
    _vendorGroups.forEach((vid, group) {
      final items = group["items"] as Map<String, dynamic>;
      items.forEach((fid, qty) => count += (qty as int));
    });
    return count;
  }

  int get itemCount => totalItemCount;

  int getItemCount(String fid) {
    int count = 0;
    _vendorGroups.forEach((vid, group) {
      final items = group["items"] as Map<String, dynamic>;
      if (items.containsKey(fid)) count += (items[fid] as int);
    });
    return count;
  }

  Map<String, Map<String, dynamic>> get vendorGroups => _vendorGroups;
}

typedef UUID = String;

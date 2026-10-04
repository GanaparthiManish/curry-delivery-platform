import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';

class WalletStore extends ChangeNotifier {
  static final WalletStore _instance = WalletStore._internal();
  factory WalletStore() => _instance;
  WalletStore._internal();

  double _balance = 0.0;

  double get balance => _balance;

  Future<void> loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final double? data = prefs.getDouble('cached_wallet_balance');
      if (data != null) {
        _balance = data;
        notifyListeners();
        debugPrint(">>> [WALLET STORE] Loaded from cache");
      }
    } catch (e) {
      debugPrint("Error loading wallet from disk: $e");
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_wallet_balance', _balance);
    } catch (e) {
      debugPrint("Error saving wallet to disk: $e");
    }
  }

  Future<void> fetchBalance() async {
    final uid = SupabaseConfig.forcedUserId ??
        SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await SupabaseConfig.client
          .from('wallets')
          .select('balance')
          .eq('user_id', uid)
          .maybeSingle();
      if (res != null) {
        updateBalance(double.tryParse(res['balance'].toString()) ?? 0.0);
      }
    } catch (e) {
      debugPrint("Fetch Wallet Error: $e");
    }
  }

  void updateBalance(double newBalance) {
    if (_balance != newBalance) {
      _balance = newBalance;
      _saveToDisk();
      notifyListeners();
    }
  }

  void clear() {
    _balance = 0.0;
    notifyListeners();
  }
}

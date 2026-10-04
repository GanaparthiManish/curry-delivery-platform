import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'core/supabase_config.dart';
import 'core/pro_theme.dart';
import 'core/location_service.dart';
import 'core/navigation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'features/auth/splash_login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/new_home_ui.dart';
import 'features/cart/cart_screen.dart';
import 'features/profile/notifications_screen.dart';
import 'features/menu/menu_screen.dart';
import 'features/menu/product_detail_screen.dart';
import 'features/home/global_search_screen.dart';
import 'core/widgets/pro_loader.dart';
import 'core/services/notification_service.dart';
import 'core/cart_state.dart';
import 'core/favorite_store.dart';
import 'core/location_store.dart';
import 'core/order_store.dart';
import 'core/menu_store.dart';
import 'core/profile_store.dart';
import 'core/wallet_store.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint(">>> [SURVIVAL] BOOT START");

    // 🛡️ INITIALIZE CRITICAL SERVICES (with safe timeouts)
    await _fastInit();

    runApp(const CustomerApp());
  }, (error, stack) {
    debugPrint(">>> [SURVIVAL] BOOT FATAL: $error");
    runApp(const CustomerApp()); // Try to run anyway
  });
}

Future<void> _fastInit() async {
  try {
    debugPrint(">>> [BOOT] Starting Infrastructure Init...");

    // 1. Core Services First (REQUIRED for everything else)
    try {
      await Future.wait([
        Firebase.initializeApp().timeout(const Duration(seconds: 4)),
        SupabaseConfig.initialize().timeout(const Duration(seconds: 4)),
      ]);
    } catch (e) {
      debugPrint(">>> [SURVIVAL] Infrastructure Init Error/Timeout: $e");
      // Keep going even if Firebase/Supabase time out, so we can init local notifs
    }

    // Always init notifications
    try {
      NotificationService.ensureNotificationsReady();
      NotificationService.initialize();
    } catch (e) {
      debugPrint(">>> [SURVIVAL] Notification Init Error: $e");
    }

    // 2. Load Local Data (Instant UI)
    await Future.wait([
      SupabaseConfig.loadSessionFromDisk(),
      LocationStore().loadFromDisk(),
      OrderStore().loadFromDisk(),
      ProfileStore().loadFromDisk(),
      WalletStore().loadFromDisk(),
    ]).timeout(const Duration(seconds: 2)).catchError((e) {
      debugPrint(">>> [SURVIVAL] Disk Load Error: $e");
      return [];
    });

    // 3. Sync Reality in Background (Only if we have a user)
    final uid = SupabaseConfig.currentUid;
    if (uid != null && uid.isNotEmpty) {
      debugPrint(">>> [BOOT] User found: $uid. Starting Background Sync.");
      // We don't await this, it runs in parallel with the UI
      SupabaseConfig.bootstrap(forceRestartHub: false);
    } else {
      debugPrint(">>> [BOOT] No user session found.");
    }

  } catch (e) {
    debugPrint(">>> [SURVIVAL] Fatal _fastInit error: $e");
  }
}

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNIV Foods',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: ProTheme.primary,
        scaffoldBackgroundColor: Colors.white,
        // Using standard font if GoogleFonts fails
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const RootDecision(),
        '/login': (context) => const SplashLoginScreen(),
        '/home': (context) => const NewHomeScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/cart': (context) => const CartScreen(),
        '/menu': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
          as Map<String, dynamic>;
          return MenuScreen(vendor: args);
        },
        '/search': (context) => const GlobalSearchScreen(),
        '/product_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ProductDetailScreen(product: args);
        },
      },
    );
  }
}

class RootDecision extends StatefulWidget {
  const RootDecision({super.key});

  @override
  State<RootDecision> createState() => _RootDecisionState();
}

class _RootDecisionState extends State<RootDecision> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _checkAndGo();
  }

  Future<void> _checkAndGo() async {
    // Navigate instantly on the next frame to avoid any perceivable lag
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigate();
    });

    // Secondary safety backup in case of weird context issues
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_ready) _navigate();
    });
  }

  void _navigate() {
    if (_ready) return;
    _ready = true;

    final String? userId = SupabaseConfig.forcedUserId;
    final String target =
        (userId != null && userId.isNotEmpty) ? '/home' : '/login';

    debugPrint(">>> [NAV] Heading to $target");

    // Using a more direct navigation approach
    Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: InkWell(
        onTap: _navigate, // 🖱️ MANUAL OVERRIDE: Tap anywhere to bypass splash
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ProLoader(message: "Initializing v8.5..."),
              const SizedBox(height: 20),
              Text(
                "Tap screen if stuck",
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

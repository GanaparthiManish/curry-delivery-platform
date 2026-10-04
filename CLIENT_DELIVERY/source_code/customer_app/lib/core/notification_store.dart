import 'package:flutter/foundation.dart';
import 'supabase_config.dart';
import 'services/notification_service.dart';

class NotificationStore extends ChangeNotifier {
  static final NotificationStore _instance = NotificationStore._internal();
  factory NotificationStore() => _instance;
  NotificationStore._internal();

  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }

  void reset() {
    _count = 0;
    notifyListeners();
  }

  void setCount(int newCount) {
    _count = newCount;
    notifyListeners();
  }

  String? _lastShownNotifId;

  Future<void> fetchLatestNotifications(List<String> userIds) async {
    try {
      final res = await SupabaseConfig.client
          .from('notifications')
          .select()
          .inFilter('user_id', userIds)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        final notifId = res['id'].toString();
        if (_lastShownNotifId != notifId) {
          _lastShownNotifId = notifId;
          
          final title = res['title']?.toString() ?? 'Order Update';
          final body = res['message']?.toString() ?? res['body']?.toString() ?? 'Your order status changed.';
          
          NotificationService.showLocalNotificationDirect(title: title, body: body);
          increment();
        }
      }
    } catch (e) {
      debugPrint(">>> [NOTIF STORE] Error fetching latest: $e");
    }
  }
}


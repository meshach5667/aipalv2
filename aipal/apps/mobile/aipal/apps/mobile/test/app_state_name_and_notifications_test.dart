import 'package:aipal/providers/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AppState personal context accessors', () {
    test('exposes wake name from profile data and reports unread notifications', () {
      final state = AppState();
      state.profile = {
        'wake_name': 'Maya',
        'display_name': 'Maya Chen',
      };
      state.notifications = [
        {'read': false, 'title': 'Today reminder'},
        {'read': true, 'title': 'Done'},
      ];

      expect(state.wakeName, 'Maya');
      expect(state.hasUnreadNotifications, isTrue);
    });
  });
}

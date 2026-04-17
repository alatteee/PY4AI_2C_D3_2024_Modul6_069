import 'package:logbook_app_069/services/preferences_service.dart';

class LoginController {
  final Map<String, String> _users = {
    'admin': '123',
    'user1': 'pass1',
    'user2': 'pass2',
  };

  Future<bool> login(String username, String password) async {
    if (_users.containsKey(username) && _users[username] == password) {
      await PreferencesService.setLastLoginUser(username);
      return true;
    }
    return false;
  }
}

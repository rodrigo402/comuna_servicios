import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const _key = 'favorites_v1';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? <String>[];
    return list.toSet();
  }

  Future<void> save(Set<String> favs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, favs.toList());
  }
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  Future<T?> loadData<T>(String key, T Function(dynamic) fromJson) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(key);

    if (cachedData != null) {
      final dynamic jsonData = jsonDecode(cachedData);
      return fromJson(jsonData);
    }

    return null;
  }

  Future<void> saveData(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = jsonEncode(data);
    prefs.setString(key, jsonData);
  }

  Future<String?> loadTitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('title');
  }
  Future<String?> loadTitleFooter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('title_footer');
  }

  Future<void> saveTitle(String title) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('title', title);
  }
  Future<void> saveTitleFooter(String title) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('title_footer', title);
  }
}

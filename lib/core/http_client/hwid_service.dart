import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class HwidService {
  static const _key = 'device_hwid';
  static String? _cached;

  /// Returns a persistent random HWID, generating one on first call.
  static Future<String> getHwid() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var hwid = prefs.getString(_key);
    if (hwid == null || hwid.isEmpty) {
      hwid = const Uuid().v4().replaceAll('-', '');
      await prefs.setString(_key, hwid);
    }
    _cached = hwid;
    return hwid;
  }

  /// Returns device OS name.
  static String get deviceOs {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Returns OS version string.
  static String get osVersion => Platform.operatingSystemVersion;

  /// Returns a map of HWID headers to send with subscription requests.
  static Future<Map<String, String>> getHeaders() async {
    final hwid = await getHwid();
    return {
      'x-hwid': hwid,
      'x-device-os': deviceOs,
      'x-ver-os': osVersion,
    };
  }
}

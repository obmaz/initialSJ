import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:initialsj/shared/models/player_profile.dart';

class LocalStorageService {
  static const String _profileKey = 'player_profile';

  /// Bumped whenever the stored shape changes, so a future migration can tell
  /// old payloads apart instead of silently discarding them.
  static const int schemaVersion = 1;
  static const String _versionField = 'schemaVersion';

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);

  Future<void> saveProfile(PlayerProfile profile) async {
    final payload = <String, dynamic>{
      ...profile.toJson(),
      _versionField: schemaVersion,
    };
    await _prefs.setString(_profileKey, jsonEncode(payload));
  }

  PlayerProfile? getProfile() {
    final jsonString = _prefs.getString(_profileKey);
    if (jsonString == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Stored profile is not a JSON object');
      }
      return PlayerProfile.fromJson(decoded);
    } catch (error, stackTrace) {
      // Returning null resets coins, best score and owned vehicles, so make
      // sure the reason is at least visible in the logs.
      debugPrint('Failed to read stored player profile: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }
}

import 'package:initialsj/shared/models/vehicle_spec.dart';

class PlayerProfile {
  final String playerId;
  final String displayName;
  final int coinBalance;
  final int level;
  final int bestScore;
  final List<String> ownedVehicleIds;
  final String selectedVehicleId;

  PlayerProfile({
    required this.playerId,
    this.displayName = 'Player 1',
    this.coinBalance = 0,
    this.level = 1,
    this.bestScore = 0,
    List<String>? ownedVehicleIds,
    this.selectedVehicleId = VehicleCatalog.starterId,
  }) : ownedVehicleIds =
           ownedVehicleIds ?? VehicleCatalog.defaultOwnedVehicleIds();

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    final ownedVehicleIds = (json['ownedVehicleIds'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final selectedVehicleId =
        json['selectedVehicleId']?.toString() ?? VehicleCatalog.starterId;

    return PlayerProfile(
      playerId:
          json['playerId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      displayName: json['displayName']?.toString() ?? 'Player 1',
      coinBalance: _asInt(json['coinBalance']),
      level: _asInt(json['level'], fallback: 1),
      bestScore: _asInt(json['bestScore']),
      ownedVehicleIds: ownedVehicleIds,
      selectedVehicleId: selectedVehicleId,
    );
  }

  /// Tolerates numbers that round-tripped through JSON as doubles or strings,
  /// so one odd field cannot throw away the whole profile.
  static int _asInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  Map<String, dynamic> toJson() {
    return {
      'playerId': playerId,
      'displayName': displayName,
      'coinBalance': coinBalance,
      'level': level,
      'bestScore': bestScore,
      'ownedVehicleIds': ownedVehicleIds,
      'selectedVehicleId': selectedVehicleId,
    };
  }

  PlayerProfile copyWith({
    String? displayName,
    int? coinBalance,
    int? level,
    int? bestScore,
    List<String>? ownedVehicleIds,
    String? selectedVehicleId,
  }) {
    return PlayerProfile(
      playerId: playerId,
      displayName: displayName ?? this.displayName,
      coinBalance: coinBalance ?? this.coinBalance,
      level: level ?? this.level,
      bestScore: bestScore ?? this.bestScore,
      ownedVehicleIds: ownedVehicleIds ?? this.ownedVehicleIds,
      selectedVehicleId: selectedVehicleId ?? this.selectedVehicleId,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:initialsj/core/services/local_storage_service.dart';
import 'package:initialsj/game/world/stage_layout.dart';
import 'package:initialsj/shared/models/player_profile.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/stage_run.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';

class AppStateController extends ChangeNotifier {
  final LocalStorageService _storage;

  PlayerProfile _profile;
  StageRun? _activeRun;
  ResultSummary? _latestResult;

  AppStateController(this._storage)
    : _profile = _normalizeProfile(
        _storage.getProfile() ??
            PlayerProfile(
              playerId: DateTime.now().millisecondsSinceEpoch.toString(),
            ),
      );

  PlayerProfile get profile => _profile;
  StageRun? get activeRun => _activeRun;
  ResultSummary? get latestResult => _latestResult;
  List<VehicleSpec> get vehicleCatalog => VehicleCatalog.vehicles;
  VehicleSpec get selectedVehicle =>
      VehicleCatalog.byId(_profile.selectedVehicleId);

  bool ownsVehicle(String vehicleId) {
    return _profile.ownedVehicleIds.contains(vehicleId);
  }

  // Profile Updates
  Future<void> updateProfile(PlayerProfile newProfile) async {
    _profile = _normalizeProfile(newProfile);
    await _storage.saveProfile(_profile);
    notifyListeners();
  }

  // Gameplay session coordination
  void startNewRun(int stageNumber) {
    final safeStageNumber = stageNumber.clamp(1, StageLayout.maxStageNumber);
    _activeRun = StageRun(
      runId: DateTime.now().millisecondsSinceEpoch.toString(),
      stageNumber: safeStageNumber,
      status: RunStatus.ready,
    );
    _latestResult = null;
    notifyListeners();
  }

  void updateActiveRun(StageRun updatedRun) {
    _activeRun = updatedRun;
    notifyListeners();
  }

  void endRun() {
    _activeRun = null;
    notifyListeners();
  }

  void setLatestResult(ResultSummary summary) {
    _latestResult = summary;
    notifyListeners();
  }

  // High score check
  Future<void> checkNewBestScore(int score) async {
    if (score > _profile.bestScore) {
      await updateProfile(_profile.copyWith(bestScore: score));
    }
  }

  // Coin updates
  Future<void> addCoins(int amount) async {
    await updateProfile(
      _profile.copyWith(coinBalance: _profile.coinBalance + amount),
    );
  }

  Future<bool> buyVehicle(String vehicleId) async {
    final vehicle = VehicleCatalog.byId(vehicleId);
    if (ownsVehicle(vehicleId) || _profile.coinBalance < vehicle.price) {
      return false;
    }

    await updateProfile(
      _profile.copyWith(
        coinBalance: _profile.coinBalance - vehicle.price,
        ownedVehicleIds: <String>[..._profile.ownedVehicleIds, vehicleId],
        selectedVehicleId: vehicleId,
      ),
    );
    return true;
  }

  Future<void> selectVehicle(String vehicleId) async {
    if (!ownsVehicle(vehicleId)) {
      return;
    }
    await updateProfile(_profile.copyWith(selectedVehicleId: vehicleId));
  }

  static PlayerProfile _normalizeProfile(PlayerProfile profile) {
    final owned = <String>{
      ...VehicleCatalog.defaultOwnedVehicleIds(),
      ...profile.ownedVehicleIds,
    }.toList();
    if (owned.isEmpty) {
      // A catalog with nothing marked startsUnlocked must not brick startup.
      owned.add(VehicleCatalog.starterId);
    }
    final selected = owned.contains(profile.selectedVehicleId)
        ? profile.selectedVehicleId
        : owned.first;

    return profile.copyWith(
      ownedVehicleIds: owned,
      selectedVehicleId: selected,
    );
  }
}

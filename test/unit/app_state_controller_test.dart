import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:initialsj/core/services/local_storage_service.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';
import 'package:initialsj/shared/state/app_state_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;
  late AppStateController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = LocalStorageService(prefs);
    controller = AppStateController(storage);
  });

  /// A vehicle that has to be bought, used to exercise the purchase paths.
  VehicleSpec lockedVehicle() =>
      VehicleCatalog.vehicles.firstWhere((vehicle) => !vehicle.startsUnlocked);

  group('initial state', () {
    test('starts with a profile and no active run', () {
      expect(controller.profile, isNotNull);
      expect(controller.activeRun, isNull);
      expect(controller.latestResult, isNull);
    });

    test('owns the starter vehicles and selects an owned one', () {
      expect(controller.ownsVehicle(VehicleCatalog.starterId), isTrue);
      expect(controller.ownsVehicle(lockedVehicle().id), isFalse);
      expect(
        controller.profile.ownedVehicleIds,
        contains(controller.profile.selectedVehicleId),
      );
    });
  });

  group('run lifecycle', () {
    test('startNewRun creates an active run and clears the last result', () {
      controller.setLatestResult(
        ResultSummary(
          finalScore: 10,
          stageNumber: 1,
          outcome: RunOutcome.failed,
          flagsCollected: 0,
          coinsAwarded: 0,
        ),
      );

      controller.startNewRun(1);

      expect(controller.activeRun, isNotNull);
      expect(controller.activeRun!.stageNumber, 1);
      expect(controller.latestResult, isNull);
    });

    test('startNewRun clamps the stage number to what exists', () {
      controller.startNewRun(9999);
      expect(controller.activeRun!.stageNumber, lessThanOrEqualTo(2));

      controller.startNewRun(0);
      expect(controller.activeRun!.stageNumber, 1);
    });

    test('endRun clears the active run', () {
      controller.startNewRun(1);
      controller.endRun();
      expect(controller.activeRun, isNull);
    });

    test('setLatestResult stores the summary', () {
      controller.setLatestResult(
        ResultSummary(
          finalScore: 1200,
          stageNumber: 1,
          outcome: RunOutcome.cleared,
          flagsCollected: 6,
          coinsAwarded: 600,
        ),
      );

      expect(controller.latestResult!.finalScore, 1200);
      expect(controller.latestResult!.flagsCollected, 6);
    });
  });

  group('coins and best score', () {
    test('addCoins accumulates and persists', () async {
      await controller.addCoins(120);
      await controller.addCoins(30);

      expect(controller.profile.coinBalance, 150);
      expect(storage.getProfile()!.coinBalance, 150);
    });

    test('checkNewBestScore only raises the best score', () async {
      await controller.checkNewBestScore(500);
      expect(controller.profile.bestScore, 500);

      await controller.checkNewBestScore(120);
      expect(controller.profile.bestScore, 500);

      await controller.checkNewBestScore(900);
      expect(controller.profile.bestScore, 900);
    });
  });

  group('vehicle purchase', () {
    test('rejects a purchase the player cannot afford', () async {
      final target = lockedVehicle();

      final bought = await controller.buyVehicle(target.id);

      expect(bought, isFalse);
      expect(controller.ownsVehicle(target.id), isFalse);
      expect(controller.profile.coinBalance, 0);
    });

    test('buys, debits the balance and selects the vehicle', () async {
      final target = lockedVehicle();
      await controller.addCoins(target.price + 50);

      final bought = await controller.buyVehicle(target.id);

      expect(bought, isTrue);
      expect(controller.ownsVehicle(target.id), isTrue);
      expect(controller.profile.coinBalance, 50);
      expect(controller.selectedVehicle.id, target.id);
    });

    test('does not charge twice for an already owned vehicle', () async {
      final target = lockedVehicle();
      await controller.addCoins(target.price * 2);
      await controller.buyVehicle(target.id);
      final balanceAfterPurchase = controller.profile.coinBalance;

      final boughtAgain = await controller.buyVehicle(target.id);

      expect(boughtAgain, isFalse);
      expect(controller.profile.coinBalance, balanceAfterPurchase);
    });

    test('a purchase survives a reload from storage', () async {
      final target = lockedVehicle();
      await controller.addCoins(target.price);
      await controller.buyVehicle(target.id);

      final reloaded = AppStateController(storage);

      expect(reloaded.ownsVehicle(target.id), isTrue);
      expect(reloaded.selectedVehicle.id, target.id);
    });
  });

  group('vehicle selection', () {
    test('ignores selection of a vehicle the player does not own', () async {
      final target = lockedVehicle();
      final before = controller.selectedVehicle.id;

      await controller.selectVehicle(target.id);

      expect(controller.selectedVehicle.id, before);
    });

    test('selects an owned vehicle', () async {
      final owned = controller.profile.ownedVehicleIds.last;

      await controller.selectVehicle(owned);

      expect(controller.selectedVehicle.id, owned);
    });
  });
}

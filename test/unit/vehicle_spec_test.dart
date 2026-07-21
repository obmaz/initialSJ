import 'package:flutter_test/flutter_test.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';

VehicleSpec specWith({
  int accelerationLevel = 5,
  int maxSpeedLevel = 5,
  int efficiencyLevel = 5,
}) {
  return VehicleSpec(
    id: 'test',
    name: 'Test',
    price: 0,
    accelerationLevel: accelerationLevel,
    maxSpeedLevel: maxSpeedLevel,
    efficiencyLevel: efficiencyLevel,
    idleDrag: 150,
    turnFriction: 2.5,
    assetName: 'vehicles/test.png',
  );
}

void main() {
  group('VehicleSpec stat scaling', () {
    test('acceleration spans the full range across levels 1 to 10', () {
      expect(specWith(accelerationLevel: 1).acceleration, 340);
      expect(specWith(accelerationLevel: 10).acceleration, 580);
    });

    test('acceleration increases monotonically', () {
      var previous = 0.0;
      for (var level = 1; level <= 10; level++) {
        final value = specWith(accelerationLevel: level).acceleration;
        expect(value, greaterThan(previous));
        previous = value;
      }
    });

    test('levels outside 1 to 10 clamp instead of extrapolating', () {
      expect(specWith(accelerationLevel: 0).acceleration, 340);
      expect(specWith(accelerationLevel: -7).acceleration, 340);
      expect(specWith(accelerationLevel: 99).acceleration, 580);
    });

    test('max speed scales linearly with its level', () {
      expect(specWith(maxSpeedLevel: 1).maxSpeed, 40);
      expect(specWith(maxSpeedLevel: 10).maxSpeed, 400);
      expect(specWith(maxSpeedLevel: 0).maxSpeed, 40);
      expect(specWith(maxSpeedLevel: 50).maxSpeed, 400);
    });

    test('higher efficiency means lower fuel drain', () {
      expect(specWith(efficiencyLevel: 1).fuelDrainMultiplier, 1.18);
      expect(specWith(efficiencyLevel: 10).fuelDrainMultiplier, 0.72);
      expect(
        specWith(efficiencyLevel: 10).fuelDrainMultiplier,
        lessThan(specWith(efficiencyLevel: 1).fuelDrainMultiplier),
      );
    });
  });

  group('VehicleCatalog', () {
    test('byId finds a catalog entry', () {
      expect(VehicleCatalog.byId('ae86').name, 'AE86');
    });

    test('byId falls back to the first vehicle for an unknown id', () {
      expect(
        VehicleCatalog.byId('does-not-exist').id,
        VehicleCatalog.starterId,
      );
    });

    test('the starter vehicle is unlocked by default', () {
      expect(
        VehicleCatalog.defaultOwnedVehicleIds(),
        contains(VehicleCatalog.starterId),
      );
    });

    test('default ownership matches the startsUnlocked flags', () {
      final expected = VehicleCatalog.vehicles
          .where((vehicle) => vehicle.startsUnlocked)
          .map((vehicle) => vehicle.id)
          .toList();

      expect(VehicleCatalog.defaultOwnedVehicleIds(), expected);
    });

    test('every catalog id is unique', () {
      final ids = VehicleCatalog.vehicles.map((vehicle) => vehicle.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}

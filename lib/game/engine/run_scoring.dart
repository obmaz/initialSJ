import 'dart:math' as math;

import 'package:initialsj/shared/models/result_summary.dart';

/// Pure scoring rules for a run.
///
/// Kept free of engine and widget dependencies so the balance can be unit
/// tested without booting Flame.
class RunScoring {
  const RunScoring._();

  static const int pointsPerFlag = 100;
  static const int penaltyPerCollision = 200;

  /// Fraction of the score paid out as coins when the run ends in failure.
  static const double failedPayoutRatio = 0.5;

  /// Never negative: a run full of collisions is worth zero, not a debt.
  static int scoreFor({required int flagsCollected, required int collisions}) {
    final raw =
        (flagsCollected * pointsPerFlag) - (collisions * penaltyPerCollision);
    return math.max(0, raw);
  }

  /// Coins follow the score, so collisions cost the player in both currencies.
  /// A failed run still pays out, but at a reduced rate.
  static int coinsFor({required int score, required RunOutcome outcome}) {
    if (outcome == RunOutcome.cleared) {
      return score;
    }
    return (score * failedPayoutRatio).floor();
  }
}

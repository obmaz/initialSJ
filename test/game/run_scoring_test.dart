import 'package:flutter_test/flutter_test.dart';
import 'package:initialsj/game/engine/run_scoring.dart';
import 'package:initialsj/shared/models/result_summary.dart';

void main() {
  group('RunScoring.scoreFor', () {
    test('awards points per flag', () {
      expect(RunScoring.scoreFor(flagsCollected: 3, collisions: 0), 300);
    });

    test('deducts a penalty per collision', () {
      expect(RunScoring.scoreFor(flagsCollected: 5, collisions: 1), 300);
    });

    test('never returns a negative score', () {
      expect(RunScoring.scoreFor(flagsCollected: 1, collisions: 10), 0);
    });

    test('is zero for an empty run', () {
      expect(RunScoring.scoreFor(flagsCollected: 0, collisions: 0), 0);
    });
  });

  group('RunScoring.coinsFor', () {
    test('pays the full score when the stage is cleared', () {
      expect(RunScoring.coinsFor(score: 450, outcome: RunOutcome.cleared), 450);
    });

    test('pays a reduced rate when the run fails', () {
      expect(RunScoring.coinsFor(score: 450, outcome: RunOutcome.failed), 225);
    });

    test('rounds the failed payout down', () {
      expect(RunScoring.coinsFor(score: 101, outcome: RunOutcome.failed), 50);
    });

    test('collisions reduce coins as well as score', () {
      final clean = RunScoring.scoreFor(flagsCollected: 4, collisions: 0);
      final crashed = RunScoring.scoreFor(flagsCollected: 4, collisions: 1);

      expect(
        RunScoring.coinsFor(score: crashed, outcome: RunOutcome.cleared),
        lessThan(
          RunScoring.coinsFor(score: clean, outcome: RunOutcome.cleared),
        ),
      );
    });
  });
}

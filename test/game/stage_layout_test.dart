import 'package:flutter_test/flutter_test.dart';
import 'package:initialsj/game/world/stage_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // col:      0123456
  const source = '''
2210022
20f0002
2P00A22
''';

  group('StageLayout.parse', () {
    final layout = StageLayout.parse(1, source);

    test('reads the grid dimensions', () {
      expect(layout.rows, 3);
      expect(layout.columns, 7);
    });

    test('locates the player spawn', () {
      expect(layout.playerSpawn.x, 1);
      expect(layout.playerSpawn.y, 2);
    });

    test('collects chaser spawns', () {
      expect(layout.chaserSpawns, hasLength(1));
      expect(layout.chaserSpawns.single.x, 4);
      expect(layout.chaserSpawns.single.y, 2);
    });

    test('counts flags', () {
      expect(layout.totalFlags, 1);
    });

    test('skips blank lines and trims whitespace', () {
      final padded = StageLayout.parse(1, '  0110  \n\n\n  0000  \n');
      expect(padded.rows, 2);
      expect(padded.columns, 4);
      expect(padded.rawLines, <String>['0110', '0000']);
    });

    test('falls back to a centred spawn when the map has no P', () {
      final spawnless = StageLayout.parse(1, '0000\n0000\n0000\n');
      expect(spawnless.playerSpawn.x, 2);
      expect(spawnless.playerSpawn.y, 1);
    });
  });

  group('StageLayout.parseRows', () {
    final layout = StageLayout.parse(1, source);

    test('derives the drivable span of each row', () {
      final chunk = layout.parseRows(0, layout.rows);
      final spans = {for (final span in chunk.roadSpans) span.row: span};

      expect(spans[0]!.startColumn, 3);
      expect(spans[0]!.endColumn, 4);
      expect(spans[1]!.startColumn, 1);
      expect(spans[1]!.endColumn, 5);
      expect(spans[2]!.startColumn, 1);
      expect(spans[2]!.endColumn, 4);
    });

    test('keeps only walls outside the drivable span', () {
      final chunk = layout.parseRows(0, 1);

      expect(chunk.walls.map((wall) => wall.col), <int>[0, 1, 2, 5, 6]);
      // Column 2 is a barrier; the rest of the row is tree tiles.
      expect(
        chunk.walls.singleWhere((wall) => wall.col == 2).type,
        WallType.barrier,
      );
      expect(chunk.walls.where((wall) => wall.type == WallType.tree).length, 4);
    });

    test('reports flags with grid coordinates', () {
      final chunk = layout.parseRows(0, layout.rows);

      expect(chunk.flags, hasLength(1));
      expect(chunk.flags.single.x, 2);
      expect(chunk.flags.single.y, 1);
    });

    test('returns only the requested row window', () {
      final chunk = layout.parseRows(1, 2);

      expect(chunk.roadSpans.map((span) => span.row), <int>[1]);
      expect(chunk.flags, hasLength(1));
    });

    test('clamps out of range windows instead of throwing', () {
      expect(layout.parseRows(-5, 999).roadSpans, hasLength(3));
      expect(layout.parseRows(2, 0).roadSpans, isEmpty);
    });
  });

  group('StageLayout assets', () {
    setUpAll(() async {
      await StageLayout.discoverAssets();
    });

    test('discovers every bundled stage', () {
      expect(StageLayout.maxStageNumber, greaterThanOrEqualTo(2));
    });

    test('resolves a stage number to the closest available stage', () {
      expect(StageLayout.resolveStageNumber(1), 1);
      expect(StageLayout.resolveStageNumber(2), 2);
      // Beyond the last stage, the last stage is reused.
      expect(StageLayout.resolveStageNumber(99), StageLayout.maxStageNumber);
      // Below the first stage, the first stage is used.
      expect(StageLayout.resolveStageNumber(0), 1);
      expect(StageLayout.resolveStageNumber(-3), 1);
    });

    test('builds the stage asset path from the resolved number', () {
      expect(StageLayout.assetPathForStage(1), 'assets/stages/stage1.txt');
      expect(StageLayout.assetPathForStage(99), 'assets/stages/stage2.txt');
    });

    test('exposes the backdrop relative to the Flame images root', () {
      expect(
        StageLayout.gameplayBackgroundAssetForStage(1),
        'assets/images/ui/bg_gameplay_1.png',
      );
      expect(
        StageLayout.gameplayBackgroundSpriteForStage(1),
        'ui/bg_gameplay_1.png',
      );
    });
  });
}

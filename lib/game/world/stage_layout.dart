import 'package:flame/components.dart';
import 'package:flutter/services.dart';

enum WallType { barrier, tree }

class StageWall {
  const StageWall({required this.col, required this.row, required this.type});

  final int col;
  final int row;
  final WallType type;
}

class StageRoadSpan {
  const StageRoadSpan({
    required this.row,
    required this.startColumn,
    required this.endColumn,
  });

  final int row;
  final int startColumn;
  final int endColumn;

  int get width => endColumn - startColumn + 1;
  double get centerColumn => (startColumn + endColumn) / 2;
}

class StageChunk {
  const StageChunk({
    required this.walls,
    required this.flags,
    required this.roadSpans,
  });

  final List<StageWall> walls;
  final List<Vector2> flags;
  final List<StageRoadSpan> roadSpans;
}

class StageLayout {
  const StageLayout({
    required this.stageNumber,
    required this.rows,
    required this.columns,
    required this.playerSpawn,
    required this.chaserSpawns,
    required this.rawLines,
    required this.totalFlags,
  });

  static const String _stageAssetPrefix = 'assets/stages/stage';
  static const String _stageAssetSuffix = '.txt';
  static const String _gameplayBackgroundPrefix =
      'assets/images/ui/bg_gameplay_';
  static const String _gameplayBackgroundSuffix = '.png';
  static List<int> _availableStageNumbers = <int>[1];
  static Set<String> _assetPaths = <String>{};

  final int stageNumber;
  final int rows;
  final int columns;
  final Vector2 playerSpawn;
  final List<Vector2> chaserSpawns;
  final List<String> rawLines;
  final int totalFlags;

  static int get maxStageNumber => _availableStageNumbers.last;

  static Future<void> discoverAssets([AssetBundle? bundle]) async {
    final assetBundle = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(assetBundle);
    final assetPaths = manifest.listAssets().toSet();
    final stageNumbers =
        assetPaths
            .where(
              (assetPath) =>
                  assetPath.startsWith(_stageAssetPrefix) &&
                  assetPath.endsWith(_stageAssetSuffix),
            )
            .map(_stageNumberFromAssetPath)
            .whereType<int>()
            .toList()
          ..sort();

    _assetPaths = assetPaths;
    _availableStageNumbers = stageNumbers.isEmpty ? <int>[1] : stageNumbers;
  }

  static String assetPathForStage(int stageNumber) {
    final resolvedStageNumber = resolveStageNumber(stageNumber);
    return 'assets/stages/stage$resolvedStageNumber.txt';
  }

  static String gameplayBackgroundAssetForStage(int stageNumber) {
    final resolvedStageNumber = resolveStageNumber(stageNumber);
    final preferredPath =
        '$_gameplayBackgroundPrefix$resolvedStageNumber$_gameplayBackgroundSuffix';
    if (_assetPaths.contains(preferredPath)) {
      return preferredPath;
    }
    return '$_gameplayBackgroundPrefix'
        '1$_gameplayBackgroundSuffix';
  }

  /// Same asset as [gameplayBackgroundAssetForStage], but relative to the
  /// `assets/images/` root that Flame's [Sprite.load] resolves against.
  static String gameplayBackgroundSpriteForStage(int stageNumber) {
    const imagesRoot = 'assets/images/';
    final path = gameplayBackgroundAssetForStage(stageNumber);
    return path.startsWith(imagesRoot)
        ? path.substring(imagesRoot.length)
        : path;
  }

  static int resolveStageNumber(int stageNumber) {
    if (_availableStageNumbers.isEmpty) {
      return 1;
    }

    final requested = stageNumber < 1 ? 1 : stageNumber;
    for (final availableStageNumber in _availableStageNumbers.reversed) {
      if (requested >= availableStageNumber) {
        return availableStageNumber;
      }
    }
    return _availableStageNumbers.first;
  }

  static Future<StageLayout> load(int stageNumber) async {
    if (_assetPaths.isEmpty) {
      await discoverAssets();
    }
    final resolvedStageNumber = resolveStageNumber(stageNumber);
    final source = await rootBundle.loadString(assetPathForStage(stageNumber));
    return parse(resolvedStageNumber, source);
  }

  static StageLayout parse(int stageNumber, String source) {
    final lines = source
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final rows = lines.length;
    final columns = lines.isEmpty ? 0 : lines.first.length;
    Vector2? playerSpawn;
    final chaserSpawns = <Vector2>[];
    var totalFlags = 0;

    for (var row = 0; row < rows; row++) {
      final line = lines[row];
      for (var col = 0; col < line.length; col++) {
        final symbol = line[col];
        switch (symbol) {
          case 'f':
          case 'F':
            totalFlags += 1;
            break;
          case 'P':
            playerSpawn = Vector2(col.toDouble(), row.toDouble());
            break;
          case 'a':
          case 'A':
          case 'b':
          case 'B':
          case 'c':
          case 'C':
            chaserSpawns.add(Vector2(col.toDouble(), row.toDouble()));
            break;
          default:
            break;
        }
      }
    }

    return StageLayout(
      stageNumber: stageNumber,
      rows: rows,
      columns: columns,
      playerSpawn: playerSpawn ?? Vector2(columns / 2, rows - 2),
      chaserSpawns: chaserSpawns,
      rawLines: lines,
      totalFlags: totalFlags,
    );
  }

  static int? _stageNumberFromAssetPath(String assetPath) {
    final fileName = assetPath.split('/').last;
    final match = RegExp(r'^stage(\d+)\.txt$').firstMatch(fileName);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  StageChunk parseRows(int startRow, int endRowExclusive) {
    final clampedStart = startRow.clamp(0, rows).toInt();
    final clampedEnd = endRowExclusive.clamp(clampedStart, rows).toInt();
    final walls = <StageWall>[];
    final flags = <Vector2>[];
    final roadSpans = <StageRoadSpan>[];

    for (var row = clampedStart; row < clampedEnd; row++) {
      final line = rawLines[row];
      int? roadStart;
      int? roadEnd;
      final pendingWalls = <StageWall>[];
      for (var col = 0; col < line.length; col++) {
        final symbol = line[col];
        final isRoadCell = symbol != '1' && symbol != '2';
        if (isRoadCell) {
          roadStart ??= col;
          roadEnd = col;
        }
        switch (symbol) {
          case '1':
            pendingWalls.add(
              StageWall(col: col, row: row, type: WallType.barrier),
            );
            break;
          case '2':
            pendingWalls.add(
              StageWall(col: col, row: row, type: WallType.tree),
            );
            break;
          case 'f':
          case 'F':
            flags.add(Vector2(col.toDouble(), row.toDouble()));
            break;
          default:
            break;
        }
      }

      if (roadStart != null && roadEnd != null) {
        roadSpans.add(
          StageRoadSpan(row: row, startColumn: roadStart, endColumn: roadEnd),
        );

        walls.addAll(
          pendingWalls.where(
            (wall) => wall.col < roadStart! || wall.col > roadEnd!,
          ),
        );
      } else {
        walls.addAll(pendingWalls);
      }
    }

    return StageChunk(walls: walls, flags: flags, roadSpans: roadSpans);
  }
}

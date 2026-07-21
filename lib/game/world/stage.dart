import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/racing_game.dart';
import 'package:initialsj/game/world/stage_layout.dart';

class Stage extends Component with HasGameReference<RacingGame> {
  static const double flagRenderScale = 1.0;
  static const int roadSegmentCount = 40;
  static const double wallRenderScale = 3.0;

  /// Rows on each side blended into a road sample, and the falloff distance
  /// used to weight them.
  static const int _smoothingRows = 2;
  static const double _smoothingFalloff = 2.5;

  static const Color _roadColorEven = Color(0xFF2A2136);
  static const Color _roadColorOdd = Color(0xFF211C2E);
  static const Color _roadShadowColor = Color(0xAA0C0D18);
  static const Color _borderColor = Color(0xFFE9D8C9);
  static const Color _laneColor = Color(0xFFF0B24A);

  /// Walls and flags are bucketed by grid row. Collision queries and rendering
  /// then touch only the rows they actually span, instead of scanning every
  /// wall in the stage (thousands) on every axis step of every actor.
  final Map<int, List<StageWall>> _wallsByRow = <int, List<StageWall>>{};
  final Map<int, List<_StageFlag>> _flagsByRow = <int, List<_StageFlag>>{};
  final List<_StageFlag> _flags = <_StageFlag>[];
  final Map<int, StageRoadSpan> _roadSpansByRow = <int, StageRoadSpan>{};

  /// Road span per row, smoothed once at load time. Sampling during render is
  /// then two array reads and a lerp rather than a weighted neighbour search.
  List<_RoadSample?> _rowSamples = const <_RoadSample?>[];

  late final StageLayout _layout;
  late final Sprite _wallTileSprite;
  late final Sprite _treeTileSprite;
  late final Sprite _flagTileSprite;

  // Cached paints. The road loop runs [roadSegmentCount] times per frame and
  // used to allocate a Paint, a LinearGradient shader and a blur MaskFilter on
  // every single iteration.
  final Paint _roadPaintEven = Paint()..color = _roadColorEven;
  final Paint _roadPaintOdd = Paint()..color = _roadColorOdd;
  final Paint _roadShadowPaint = Paint()..color = _roadShadowColor;
  final Paint _lanePaint = Paint()..color = _laneColor;
  final Paint _islandShadowPaint = Paint()..color = const Color(0x880A2418);
  final Paint _highlightPaint = Paint()
    ..color = const Color(0x18FFFFFF)
    ..blendMode = BlendMode.screen;
  final Paint _borderPaint = Paint()
    ..color = _borderColor
    ..style = PaintingStyle.stroke;

  // Reused across frames so projecting the road strip allocates nothing.
  final List<Offset> _leftEdge = List<Offset>.filled(
    roadSegmentCount + 1,
    Offset.zero,
    growable: false,
  );
  final List<Offset> _rightEdge = List<Offset>.filled(
    roadSegmentCount + 1,
    Offset.zero,
    growable: false,
  );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _wallTileSprite = await Sprite.load('tiles/tile_wall.webp');
    _treeTileSprite = await Sprite.load('tiles/tile_tree.webp');
    _flagTileSprite = await Sprite.load('tiles/tile_flag.webp');
    _layout = await StageLayout.load(game.stageNumber);
    _buildArena();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    _renderRoad(canvas);
    _renderWorldObjects(canvas);
  }

  // Geometry ------------------------------------------------------------

  double get cellSize => (game.size.x * 0.85) / 6.0;
  double get gridLeft => 0.0;
  double get gridTop => 0.0;
  double get gridWidth => cellSize * _layout.columns;
  double get gridHeight => cellSize * _layout.rows;
  double get gridRight => gridLeft + gridWidth;
  double get gridBottom => gridTop + gridHeight;
  int get totalFlags => _layout.totalFlags;
  Vector2 get playerSpawnPoint => _gridToWorld(_layout.playerSpawn);
  List<Vector2> get chaserSpawnPoints =>
      _layout.chaserSpawns.map(_gridToWorld).toList();
  List<String> get miniMapRows => List.unmodifiable(_layout.rawLines);
  List<Vector2> get remainingFlagPositions => _flags
      .where((flag) => !flag.collected)
      .map((flag) => _flagWorldPosition(flag))
      .toList(growable: false);

  double roadCenterRatioForWorldY(double worldY) {
    final sample = _roadSampleForWorldY(worldY);
    if (sample == null || _layout.columns <= 0) {
      return 0.5;
    }
    return ((sample.centerColumn + 0.5) / _layout.columns).clamp(0.0, 1.0);
  }

  double roadWidthRatioForWorldY(double worldY) {
    final sample = _roadSampleForWorldY(worldY);
    if (sample == null || _layout.columns <= 0) {
      return 1.0;
    }
    return (sample.width / _layout.columns).clamp(0.18, 1.0);
  }

  double roadLeftForWorldY(double worldY) {
    final sample = _roadSampleForWorldY(worldY);
    if (sample == null) {
      return gridLeft;
    }
    return gridLeft + (sample.startColumn * cellSize);
  }

  double roadRightForWorldY(double worldY) {
    final sample = _roadSampleForWorldY(worldY);
    if (sample == null) {
      return gridRight;
    }
    return gridLeft + ((sample.endColumn + 1) * cellSize);
  }

  double roadCenterWorldXForWorldY(double worldY) {
    return (roadLeftForWorldY(worldY) + roadRightForWorldY(worldY)) / 2;
  }

  double roadWidthWorldForWorldY(double worldY) {
    return roadRightForWorldY(worldY) - roadLeftForWorldY(worldY);
  }

  Vector2 clampToRoad(Vector2 position, Vector2 size) {
    return Vector2(
      position.x.clamp(gridLeft + size.x / 2, gridRight - size.x / 2),
      position.y.clamp(gridTop + size.y / 2, gridBottom - size.y / 2),
    );
  }

  double progressFor(Vector2 position) {
    if (gridHeight <= 0) {
      return 0.0;
    }
    return (1 - (position.y / gridHeight)).clamp(0.0, 1.0);
  }

  // Collision -----------------------------------------------------------

  bool collidesWithWall(Rect rect) {
    final cell = cellSize;
    if (cell <= 0 || _wallsByRow.isEmpty) {
      return false;
    }

    final startRow = (rect.top / cell).floor();
    final endRow = (rect.bottom / cell).floor();
    for (var row = startRow; row <= endRow; row++) {
      final bucket = _wallsByRow[row];
      if (bucket == null) {
        continue;
      }
      for (final wall in bucket) {
        if (rect.overlaps(_wallRect(wall, cell))) {
          return true;
        }
      }
    }
    return false;
  }

  int collectFlags(Rect rect) {
    final cell = cellSize;
    if (cell <= 0) {
      return 0;
    }

    var count = 0;
    final startRow = (rect.top / cell).floor();
    final endRow = (rect.bottom / cell).floor();
    for (var row = startRow; row <= endRow; row++) {
      final bucket = _flagsByRow[row];
      if (bucket == null) {
        continue;
      }
      for (final flag in bucket) {
        if (flag.collected) {
          continue;
        }
        final position = _flagWorldPosition(flag);
        if (rect.contains(Offset(position.x, position.y))) {
          flag.collected = true;
          count += 1;
        }
      }
    }
    return count;
  }

  // Rendering -----------------------------------------------------------

  void _renderRoad(Canvas canvas) {
    _renderNearSkirt(canvas);
    _projectRoadEdges();

    // Segments are painted far to near so nearer geometry overdraws farther
    // geometry, matching the painter's-algorithm depth order.
    for (var index = roadSegmentCount; index >= 1; index--) {
      final nearLeft = _leftEdge[index - 1];
      final nearRight = _rightEdge[index - 1];
      final farLeft = _leftEdge[index];
      final farRight = _rightEdge[index];

      canvas.drawPath(
        _quadPath(farLeft, nearLeft, nearRight, farRight),
        index.isEven ? _roadPaintEven : _roadPaintOdd,
      );
    }

    // One shadow pass over the whole strip. This used to be a blurred fill per
    // segment: 40 offscreen blur passes every frame.
    canvas.drawPath(_stripPath(), _roadShadowPaint);

    for (var index = roadSegmentCount; index >= 1; index--) {
      final nearLeft = _leftEdge[index - 1];
      final nearRight = _rightEdge[index - 1];
      final farLeft = _leftEdge[index];
      final farRight = _rightEdge[index];

      _borderPaint.strokeWidth = lerpDouble(
        1.4,
        4.2,
        index / roadSegmentCount,
      )!;
      canvas.drawLine(
        Offset(farLeft.dx + 1, farLeft.dy),
        Offset(nearLeft.dx + 1, nearLeft.dy),
        _borderPaint,
      );
      canvas.drawLine(
        Offset(farRight.dx - 1, farRight.dy),
        Offset(nearRight.dx - 1, nearRight.dy),
        _borderPaint,
      );

      final nearRoadWidth = nearRight.dx - nearLeft.dx;
      final farRoadWidth = farRight.dx - farLeft.dx;

      if (index.isOdd) {
        final nearCenterX = (nearLeft.dx + nearRight.dx) / 2;
        final farCenterX = (farLeft.dx + farRight.dx) / 2;
        final nearLaneHalfWidth = (nearRoadWidth * 0.045).clamp(0.0, 5.5);
        final farLaneHalfWidth = (farRoadWidth * 0.045).clamp(0.0, 2.5);
        canvas.drawPath(
          _quadPath(
            Offset(farCenterX - farLaneHalfWidth, farLeft.dy),
            Offset(nearCenterX - nearLaneHalfWidth, nearLeft.dy),
            Offset(nearCenterX + nearLaneHalfWidth, nearLeft.dy),
            Offset(farCenterX + farLaneHalfWidth, farLeft.dy),
          ),
          _lanePaint,
        );
      }

      final farHighlightInset = (farRoadWidth * 0.26).clamp(0.0, 18.0);
      final nearHighlightInset = (nearRoadWidth * 0.24).clamp(0.0, 34.0);
      if (nearHighlightInset * 2 < nearRoadWidth &&
          farHighlightInset * 2 < farRoadWidth) {
        canvas.drawPath(
          _quadPath(
            Offset(farLeft.dx + farHighlightInset, farLeft.dy),
            Offset(nearLeft.dx + nearHighlightInset, nearLeft.dy),
            Offset(nearRight.dx - nearHighlightInset, nearRight.dy),
            Offset(farRight.dx - farHighlightInset, farRight.dy),
          ),
          _highlightPaint,
        );
      }
    }
  }

  /// Fills the wedge between the nearest projected segment and the bottom of
  /// the screen, which sits behind the player sprite.
  void _renderNearSkirt(Canvas canvas) {
    final bottomY = game.size.y;
    final nearWorldY = game.playerWorldPosition.y;
    final totalStageColumns = gridWidth / cellSize;
    final roadCellCount =
        roadWidthRatioForWorldY(nearWorldY) * totalStageColumns;
    final visibleCellWidth = game.size.x / RacingGame.targetVisibleStageCells;
    final roadWidth = visibleCellWidth * roadCellCount;
    final centerX = game.roadCenterXForWorldY(nearWorldY);
    final topY = bottomY - (cellSize * 0.55);
    final left = centerX - (roadWidth / 2);
    final right = centerX + (roadWidth / 2);

    canvas.drawRect(Rect.fromLTRB(left, topY, right, bottomY), _roadPaintEven);

    _borderPaint.strokeWidth = 4.2;
    canvas.drawLine(
      Offset(left + 1, topY),
      Offset(left + 1, bottomY),
      _borderPaint,
    );
    canvas.drawLine(
      Offset(right - 1, topY),
      Offset(right - 1, bottomY),
      _borderPaint,
    );
  }

  /// Projects each segment boundary exactly once. The previous implementation
  /// projected the near and far edge of every segment separately, doing the
  /// work for every shared boundary twice.
  void _projectRoadEdges() {
    final playerWorldY = game.playerWorldPosition.y;
    final nearestDepth = -cellSize * 3.2;
    for (var index = 0; index <= roadSegmentCount; index++) {
      final depth = lerpDouble(
        nearestDepth,
        game.visibleDepth,
        index / roadSegmentCount,
      )!;
      final worldY = playerWorldY - depth;
      _leftEdge[index] = game.projectWorldPosition(
        Vector2(roadLeftForWorldY(worldY), worldY),
      );
      _rightEdge[index] = game.projectWorldPosition(
        Vector2(roadRightForWorldY(worldY), worldY),
      );
    }
  }

  Path _quadPath(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  Path _stripPath() {
    final path = Path()..moveTo(_leftEdge[0].dx, _leftEdge[0].dy);
    for (var index = 1; index <= roadSegmentCount; index++) {
      path.lineTo(_leftEdge[index].dx, _leftEdge[index].dy);
    }
    for (var index = roadSegmentCount; index >= 0; index--) {
      path.lineTo(_rightEdge[index].dx, _rightEdge[index].dy);
    }
    return path..close();
  }

  void _renderWorldObjects(Canvas canvas) {
    final cell = cellSize;
    if (cell <= 0) {
      return;
    }

    final nearWorldY = game.playerWorldPosition.y;
    final farWorldY = nearWorldY - game.visibleDepth;
    final startRow = (farWorldY / cell).floor().clamp(0, _layout.rows);
    final endRow = (nearWorldY / cell).ceil().clamp(0, _layout.rows);

    // Far rows first so nearer sprites overlap them.
    for (var row = startRow; row <= endRow; row++) {
      final bucket = _wallsByRow[row];
      if (bucket == null) {
        continue;
      }
      for (final wall in bucket) {
        final rect = _wallRect(wall, cell);
        final centerY = rect.center.dy;
        if (!game.isWithinPseudoView(centerY)) {
          continue;
        }
        final projected = game.projectWorldPosition(
          Vector2(rect.center.dx, centerY),
        );
        final scale = game.perspectiveScaleForWorldY(centerY);
        final spriteSize = cell * scale * wallRenderScale;
        canvas.drawOval(
          Rect.fromCenter(
            center: projected.translate(0, spriteSize * 0.32),
            width: spriteSize * 0.9,
            height: spriteSize * 0.22,
          ),
          _islandShadowPaint,
        );
        final drawRect = Rect.fromCenter(
          center: projected.translate(0, -spriteSize * 0.2),
          width: spriteSize,
          height: spriteSize,
        );
        if (wall.type == WallType.tree) {
          _treeTileSprite.renderRect(canvas, drawRect);
        } else {
          _wallTileSprite.renderRect(canvas, drawRect);
        }
      }
    }

    // Flags render above every wall, as they did when both were sorted lists.
    for (var row = startRow; row <= endRow; row++) {
      final bucket = _flagsByRow[row];
      if (bucket == null) {
        continue;
      }
      for (final flag in bucket) {
        if (flag.collected) {
          continue;
        }
        final position = _flagWorldPosition(flag);
        if (!game.isWithinPseudoView(position.y)) {
          continue;
        }
        final projected = game.projectWorldPosition(position);
        final scale = game.perspectiveScaleForWorldY(position.y);
        _flagTileSprite.renderRect(
          canvas,
          Rect.fromCenter(
            center: projected.translate(0, -cell * scale * 0.35),
            width: cell * flagRenderScale * scale,
            height: cell * flagRenderScale * scale,
          ),
        );
      }
    }

    _renderStartMarker(canvas);
  }

  void _renderStartMarker(Canvas canvas) {
    final startY = playerSpawnPoint.y;
    if (!game.isWithinPseudoView(startY)) {
      return;
    }

    final left = game.projectWorldPosition(
      Vector2(roadLeftForWorldY(startY), startY),
    );
    final right = game.projectWorldPosition(
      Vector2(roadRightForWorldY(startY), startY),
    );
    final centerX = (left.dx + right.dx) / 2;
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'START',
        style: TextStyle(
          color: Color(0xFFFF4D4D),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.drawRect(
      Rect.fromLTWH(left.dx, left.dy - 2, right.dx - left.dx, 4),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    textPainter.paint(
      canvas,
      Offset(centerX - (textPainter.width / 2), left.dy - 20),
    );
  }

  // Loading -------------------------------------------------------------

  /// Stages are a few hundred rows, so the whole layout is built up front.
  /// The previous chunked loader never actually streamed: its 500 row initial
  /// window always covered the entire stage, leaving the incremental path dead
  /// and untested.
  void _buildArena() {
    _clearArena();

    final chunk = _layout.parseRows(0, _layout.rows);

    for (final wall in chunk.walls) {
      (_wallsByRow[wall.row] ??= <StageWall>[]).add(wall);
    }

    for (final cell in chunk.flags) {
      final flag = _StageFlag(cell.x.round(), cell.y.round());
      _flags.add(flag);
      (_flagsByRow[flag.row] ??= <_StageFlag>[]).add(flag);
    }

    for (final roadSpan in chunk.roadSpans) {
      _roadSpansByRow[roadSpan.row] = roadSpan;
    }

    _rebuildRowSamples();
  }

  void _clearArena() {
    _wallsByRow.clear();
    _flagsByRow.clear();
    _flags.clear();
    _roadSpansByRow.clear();
  }

  /// Resolves the nearest defined road span for every row and pre-blends the
  /// smoothing window, so sampling at render time is O(1).
  void _rebuildRowSamples() {
    final rowCount = _layout.rows;
    if (rowCount <= 0) {
      _rowSamples = const <_RoadSample?>[];
      return;
    }

    // Two wrap-around sweeps replace the old per-lookup linear search for the
    // closest row that actually has a span.
    final backward = List<int>.filled(rowCount, -1);
    var last = -1;
    for (var pass = 0; pass < 2; pass++) {
      for (var row = 0; row < rowCount; row++) {
        if (_roadSpansByRow.containsKey(row)) {
          last = row;
        }
        if (pass == 1) {
          backward[row] = last;
        }
      }
    }

    final forward = List<int>.filled(rowCount, -1);
    last = -1;
    for (var pass = 0; pass < 2; pass++) {
      for (var row = rowCount - 1; row >= 0; row--) {
        if (_roadSpansByRow.containsKey(row)) {
          last = row;
        }
        if (pass == 1) {
          forward[row] = last;
        }
      }
    }

    final nearest = List<StageRoadSpan?>.filled(rowCount, null);
    for (var row = 0; row < rowCount; row++) {
      final before = backward[row];
      final after = forward[row];
      if (before < 0 && after < 0) {
        continue;
      }
      if (before < 0) {
        nearest[row] = _roadSpansByRow[after];
      } else if (after < 0) {
        nearest[row] = _roadSpansByRow[before];
      } else {
        final beforeDistance = _wrapRow(row - before);
        final afterDistance = _wrapRow(after - row);
        nearest[row] =
            _roadSpansByRow[beforeDistance <= afterDistance ? before : after];
      }
    }

    final samples = List<_RoadSample?>.filled(rowCount, null);
    for (var row = 0; row < rowCount; row++) {
      var weightedStart = 0.0;
      var weightedEnd = 0.0;
      var totalWeight = 0.0;
      for (var offset = -_smoothingRows; offset <= _smoothingRows; offset++) {
        final span = nearest[_wrapRow(row + offset)];
        if (span == null) {
          continue;
        }
        final weight = 1.0 - (offset.abs() / _smoothingFalloff);
        if (weight <= 0) {
          continue;
        }
        weightedStart += span.startColumn * weight;
        weightedEnd += span.endColumn * weight;
        totalWeight += weight;
      }
      if (totalWeight > 0) {
        samples[row] = _RoadSample(
          startColumn: weightedStart / totalWeight,
          endColumn: weightedEnd / totalWeight,
        );
      }
    }

    _rowSamples = samples;
  }

  // Internals -----------------------------------------------------------

  Rect _wallRect(StageWall wall, double cell) => Rect.fromLTWH(
    gridLeft + (wall.col * cell),
    gridTop + (wall.row * cell),
    cell,
    cell,
  );

  Vector2 _flagWorldPosition(_StageFlag flag) =>
      _gridToWorld(Vector2(flag.col.toDouble(), flag.row.toDouble()));

  Vector2 _gridToWorld(Vector2 cell) {
    return Vector2(
      gridLeft + (cell.x * cellSize) + (cellSize / 2),
      gridTop + (cell.y * cellSize) + (cellSize / 2),
    );
  }

  /// Interpolates between the two pre-smoothed neighbouring rows, so road
  /// curvature stays continuous as the player moves within a cell.
  _RoadSample? _roadSampleForWorldY(double worldY) {
    final height = gridHeight;
    if (_rowSamples.isEmpty || height <= 0 || cellSize <= 0) {
      return null;
    }

    final wrappedWorldY = ((worldY % height) + height) % height;
    final rowPosition = wrappedWorldY / cellSize;
    final lowRow = _wrapRow(rowPosition.floor());
    final highRow = _wrapRow(lowRow + 1);
    final t = rowPosition - rowPosition.floorToDouble();

    final low = _rowSamples[lowRow];
    final high = _rowSamples[highRow];
    if (low == null) {
      return high;
    }
    if (high == null) {
      return low;
    }
    return _RoadSample(
      startColumn: low.startColumn + ((high.startColumn - low.startColumn) * t),
      endColumn: low.endColumn + ((high.endColumn - low.endColumn) * t),
    );
  }

  int _wrapRow(int row) {
    final rowCount = _layout.rows;
    if (rowCount <= 0) {
      return 0;
    }
    return ((row % rowCount) + rowCount) % rowCount;
  }
}

class _RoadSample {
  const _RoadSample({required this.startColumn, required this.endColumn});

  final double startColumn;
  final double endColumn;

  double get width => endColumn - startColumn + 1;
  double get centerColumn => (startColumn + endColumn) / 2;
}

/// Flags keep grid coordinates rather than a baked world rect, so they follow
/// [Stage.cellSize] when the viewport is resized.
class _StageFlag {
  _StageFlag(this.col, this.row);

  final int col;
  final int row;
  bool collected = false;
}

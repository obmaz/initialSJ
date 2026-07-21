import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/camera_centered_game.dart';
import 'package:initialsj/game/world/stage_layout.dart';

class CameraCenteredStage extends Component
    with HasGameReference<CameraCenteredGame> {
  static const double flagRenderScale = 1.0;
  static const int initialLoadedRowCount = 500;
  static const int additionalLoadedRowCount = 250;

  final List<_StageWall> _walls = <_StageWall>[];
  final List<_StageFlag> _flags = <_StageFlag>[];
  final Map<int, StageRoadSpan> _roadSpansByRow = <int, StageRoadSpan>{};

  late final StageLayout _layout;
  late final Sprite _wallTileSprite;
  late final Sprite _treeTileSprite;
  late final Sprite _flagTileSprite;
  late int _loadedStartRow;
  late int _nextLoadTriggerRow;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _wallTileSprite = await Sprite.load('tiles/tile_wall.webp');
    _treeTileSprite = await Sprite.load('tiles/tile_tree.webp');
    _flagTileSprite = await Sprite.load('tiles/tile_flag.webp');
    _layout = await StageLayout.load(game.stageNumber);
    _buildInitialArena();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) {
      return;
    }
    _maybeLoadMoreRows();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    _renderBackdrop(canvas);
    _renderRoad(canvas);
    _renderWorldObjects(canvas);
  }

  void _renderBackdrop(Canvas canvas) {
    // Background is rendered by the gameplay screen for parallax control.
  }

  void _renderRoad(Canvas canvas) {
    const segmentCount = 40;
    final shoulderPaint = Paint()..color = const Color(0xFF7A302F);
    final borderPaint = Paint()..color = const Color(0xFFE9D8C9);
    const shoulderInset = 0.0;
    final bottomY = game.size.y;
    final baseNearWorldY = game.playerWorldPosition.y;
    final roadWidthRatio = roadWidthRatioForWorldY(baseNearWorldY);
    final totalStageColumns = gridWidth / cellSize;
    final roadCellCount = roadWidthRatio * totalStageColumns;
    final visibleCellWidth =
        game.size.x / CameraCenteredGame.targetVisibleStageCells;
    final baseRoadWidth = visibleCellWidth * roadCellCount;
    final baseShoulderWidth = baseRoadWidth + (shoulderInset * 2);
    final baseCenterX = game.roadCenterXForWorldY(baseNearWorldY);
    final baseLeft = Offset(
      baseCenterX - (baseShoulderWidth / 2),
      bottomY - (cellSize * 0.55),
    );
    final baseRight = Offset(
      baseCenterX + (baseShoulderWidth / 2),
      bottomY - (cellSize * 0.55),
    );
    final baseRoadLeft = baseCenterX - (baseRoadWidth / 2);
    final baseRoadRight = baseCenterX + (baseRoadWidth / 2);

    canvas.drawPath(
      Path()
        ..moveTo(baseLeft.dx, baseLeft.dy)
        ..lineTo(baseRight.dx, baseRight.dy)
        ..lineTo(baseRight.dx, bottomY)
        ..lineTo(baseLeft.dx, bottomY)
        ..close(),
      shoulderPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(baseRoadLeft, baseLeft.dy)
        ..lineTo(baseRoadRight, baseRight.dy)
        ..lineTo(baseRoadRight, bottomY)
        ..lineTo(baseRoadLeft, bottomY)
        ..close(),
      Paint()..color = const Color(0xFF201B2E),
    );
    canvas.drawPath(
      Path()
        ..moveTo(baseRoadLeft + 1, baseLeft.dy)
        ..lineTo(baseRoadLeft + 1, bottomY),
      borderPaint
        ..strokeWidth = 4.2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(baseRoadRight - 1, baseRight.dy)
        ..lineTo(baseRoadRight - 1, bottomY),
      borderPaint
        ..strokeWidth = 4.2
        ..style = PaintingStyle.stroke,
    );

    for (var index = segmentCount; index >= 1; index--) {
      final nearDepth = lerpDouble(
        -cellSize * 3.2,
        game.visibleDepth,
        (index - 1) / segmentCount,
      )!;
      final farDepth = lerpDouble(
        -cellSize * 3.2,
        game.visibleDepth,
        index / segmentCount,
      )!;
      final nearWorldY = game.playerWorldPosition.y - nearDepth;
      final farWorldY = game.playerWorldPosition.y - farDepth;
      final nearLeft = game.projectWorldPosition(
        Vector2(roadLeftForWorldY(nearWorldY), nearWorldY),
      );
      final nearRight = game.projectWorldPosition(
        Vector2(roadRightForWorldY(nearWorldY), nearWorldY),
      );
      final farLeft = game.projectWorldPosition(
        Vector2(roadLeftForWorldY(farWorldY), farWorldY),
      );
      final farRight = game.projectWorldPosition(
        Vector2(roadRightForWorldY(farWorldY), farWorldY),
      );

      final shoulderPath = Path()
        ..moveTo(farLeft.dx, farLeft.dy)
        ..lineTo(nearLeft.dx, nearLeft.dy)
        ..lineTo(nearRight.dx, nearRight.dy)
        ..lineTo(farRight.dx, farRight.dy)
        ..close();
      canvas.drawPath(shoulderPath, shoulderPaint);

      final roadPath = Path()
        ..moveTo(farLeft.dx + shoulderInset, farLeft.dy)
        ..lineTo(nearLeft.dx + shoulderInset, nearLeft.dy)
        ..lineTo(nearRight.dx - shoulderInset, nearRight.dy)
        ..lineTo(farRight.dx - shoulderInset, farRight.dy)
        ..close();
      final roadRect = Rect.fromLTRB(
        farLeft.dx,
        farLeft.dy,
        nearRight.dx,
        nearRight.dy,
      );
      final roadPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            index.isEven ? const Color(0xFF33273E) : const Color(0xFF2A223A),
            index.isEven ? const Color(0xFF201B2E) : const Color(0xFF171522),
          ],
        ).createShader(roadRect);
      canvas.drawPath(roadPath, roadPaint);

      final roadShadowPaint = Paint()
        ..color = const Color(0xAA0C0D18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(
        Path()
          ..moveTo(farLeft.dx + shoulderInset, farLeft.dy)
          ..lineTo(nearLeft.dx + shoulderInset, nearLeft.dy)
          ..lineTo(nearRight.dx - shoulderInset, nearRight.dy)
          ..lineTo(farRight.dx - shoulderInset, farRight.dy)
          ..close(),
        roadShadowPaint,
      );

      final leftBorderPath = Path()
        ..moveTo(farLeft.dx + shoulderInset + 1, farLeft.dy)
        ..lineTo(nearLeft.dx + shoulderInset + 1, nearLeft.dy);
      final rightBorderPath = Path()
        ..moveTo(farRight.dx - shoulderInset - 1, farRight.dy)
        ..lineTo(nearRight.dx - shoulderInset - 1, nearRight.dy);
      canvas.drawPath(
        leftBorderPath,
        borderPaint
          ..strokeWidth = lerpDouble(1.4, 4.2, index / segmentCount)!
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        rightBorderPath,
        borderPaint
          ..strokeWidth = lerpDouble(1.4, 4.2, index / segmentCount)!
          ..style = PaintingStyle.stroke,
      );

      final nearRoadWidth = nearRight.dx - nearLeft.dx;
      final farRoadWidth = farRight.dx - farLeft.dx;

      if (index.isOdd) {
        final nearCenterX = (nearLeft.dx + nearRight.dx) / 2;
        final farCenterX = (farLeft.dx + farRight.dx) / 2;
        final nearLaneHalfWidth = math.min(nearRoadWidth * 0.045, 5.5);
        final farLaneHalfWidth = math.min(farRoadWidth * 0.045, 2.5);
        final lanePath = Path()
          ..moveTo(farCenterX - farLaneHalfWidth, farLeft.dy)
          ..lineTo(nearCenterX - nearLaneHalfWidth, nearLeft.dy)
          ..lineTo(nearCenterX + nearLaneHalfWidth, nearLeft.dy)
          ..lineTo(farCenterX + farLaneHalfWidth, farLeft.dy)
          ..close();
        canvas.drawPath(lanePath, Paint()..color = const Color(0xFFF0B24A));
      }

      final farHighlightInset = math.min(farRoadWidth * 0.26, 18.0);
      final nearHighlightInset = math.min(nearRoadWidth * 0.24, 34.0);
      final highlightPath = Path()
        ..moveTo(farLeft.dx + shoulderInset + farHighlightInset, farLeft.dy)
        ..lineTo(nearLeft.dx + shoulderInset + nearHighlightInset, nearLeft.dy)
        ..lineTo(
          nearRight.dx - shoulderInset - nearHighlightInset,
          nearRight.dy,
        )
        ..lineTo(farRight.dx - shoulderInset - farHighlightInset, farRight.dy)
        ..close();
      if (nearHighlightInset * 2 < nearRoadWidth &&
          farHighlightInset * 2 < farRoadWidth) {
        canvas.drawPath(
          highlightPath,
          Paint()
            ..color = const Color(0x18FFFFFF)
            ..blendMode = BlendMode.screen,
        );
      }
    }
  }

  void _renderWorldObjects(Canvas canvas) {
    final visibleWalls =
        _walls
            .where((wall) => game.isWithinPseudoView(wall.rect.center.dy))
            .toList()
          ..sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy));
    final visibleFlags =
        _flags
            .where(
              (flag) =>
                  !flag.collected && game.isWithinPseudoView(flag.position.y),
            )
            .toList()
          ..sort((a, b) => a.position.y.compareTo(b.position.y));

    final islandShadowPaint = Paint()..color = const Color(0x880A2418);

    for (final wall in visibleWalls) {
      final projected = game.projectWorldPosition(
        Vector2(wall.rect.center.dx, wall.rect.center.dy),
      );
      final scale = game.perspectiveScaleForWorldY(wall.rect.center.dy);
      final spriteSize = cellSize * scale * 3.0;
      final drawRect = Rect.fromCenter(
        center: projected.translate(0, -spriteSize * 0.2),
        width: spriteSize,
        height: spriteSize,
      );
      final shadowRect = Rect.fromCenter(
        center: projected.translate(0, spriteSize * 0.32),
        width: spriteSize * 0.9,
        height: spriteSize * 0.22,
      );
      canvas.drawOval(shadowRect, islandShadowPaint);

      if (wall.type == WallType.tree) {
        _treeTileSprite.renderRect(canvas, drawRect);
      } else {
        _wallTileSprite.renderRect(canvas, drawRect);
      }
    }

    for (final flag in visibleFlags) {
      final projected = game.projectWorldPosition(flag.position);
      final scale = game.perspectiveScaleForWorldY(flag.position.y);
      final rect = Rect.fromCenter(
        center: projected.translate(0, -cellSize * scale * 0.35),
        width: cellSize * flagRenderScale * scale,
        height: cellSize * flagRenderScale * scale,
      );
      _flagTileSprite.renderRect(canvas, rect);
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
    final bannerPaint = Paint()..color = const Color(0xCCFFFFFF);
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
      bannerPaint,
    );
    textPainter.paint(
      canvas,
      Offset(centerX - (textPainter.width / 2), left.dy - 20),
    );
  }

  double get cellSize => (game.size.x * 0.85) / 6.0;
  double get gridLeft => 0.0;
  double get gridTop => 0.0;
  double get gridWidth => cellSize * _layout.columns;
  double get gridHeight => cellSize * _layout.rows;
  double get gridRight => gridLeft + gridWidth;
  double get gridBottom => gridTop + gridHeight;
  int get totalFlags => _layout.totalFlags;
  int get collectedFlags => _flags.where((flag) => flag.collected).length;
  Vector2 get playerSpawnPoint => _gridToWorld(_layout.playerSpawn);
  List<Vector2> get chaserSpawnPoints =>
      _layout.chaserSpawns.map(_gridToWorld).toList();
  List<String> get miniMapRows => List.unmodifiable(_layout.rawLines);
  List<Vector2> get remainingFlagPositions => _flags
      .where((flag) => !flag.collected)
      .map((flag) => flag.position.clone())
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

  bool collidesWithWall(Rect rect) {
    for (final wall in _walls) {
      if (wall.rect.right < rect.left ||
          wall.rect.left > rect.right ||
          wall.rect.bottom < rect.top ||
          wall.rect.top > rect.bottom) {
        continue;
      }
      if (rect.overlaps(wall.rect)) {
        return true;
      }
    }
    return false;
  }

  int collectFlags(Rect rect) {
    var count = 0;
    for (final flag in _flags) {
      if (!flag.collected &&
          rect.contains(Offset(flag.position.x, flag.position.y))) {
        flag.collected = true;
        count += 1;
      }
    }
    return count;
  }

  double progressFor(Vector2 position) {
    if (gridHeight <= 0) {
      return 0.0;
    }
    return (1 - (position.y / gridHeight)).clamp(0.0, 1.0);
  }

  void _buildInitialArena() {
    _walls.clear();
    _flags.clear();
    _roadSpansByRow.clear();

    _loadedStartRow = (_layout.rows - initialLoadedRowCount)
        .clamp(0, _layout.rows)
        .toInt();
    _appendRows(_loadedStartRow, _layout.rows);

    final initialLoadedRows = _layout.rows - _loadedStartRow;
    _nextLoadTriggerRow = _loadedStartRow + (initialLoadedRows / 2).floor();
  }

  void _maybeLoadMoreRows() {
    if (_loadedStartRow <= 0) {
      return;
    }

    final playerRow = (game.playerWorldPosition.y / cellSize)
        .floor()
        .clamp(0, _layout.rows - 1)
        .toInt();
    if (playerRow > _nextLoadTriggerRow) {
      return;
    }

    final nextStart = (_loadedStartRow - additionalLoadedRowCount)
        .clamp(0, _loadedStartRow)
        .toInt();
    if (nextStart == _loadedStartRow) {
      return;
    }

    _appendRows(nextStart, _loadedStartRow);
    _loadedStartRow = nextStart;
    _nextLoadTriggerRow =
        _loadedStartRow + (additionalLoadedRowCount / 2).floor();
  }

  void _appendRows(int startRow, int endRowExclusive) {
    final chunk = _layout.parseRows(startRow, endRowExclusive);

    _walls.addAll(
      chunk.walls.map(
        (wall) => _StageWall(
          rect: Rect.fromLTWH(
            gridLeft + (wall.col * cellSize),
            gridTop + (wall.row * cellSize),
            cellSize,
            cellSize,
          ),
          type: wall.type,
        ),
      ),
    );

    _flags.addAll(chunk.flags.map((flag) => _StageFlag(_gridToWorld(flag))));
    for (final roadSpan in chunk.roadSpans) {
      _roadSpansByRow[roadSpan.row] = roadSpan;
    }
  }

  Vector2 _gridToWorld(Vector2 cell) {
    return Vector2(
      gridLeft + (cell.x * cellSize) + (cellSize / 2),
      gridTop + (cell.y * cellSize) + (cellSize / 2),
    );
  }

  _RoadSample? _roadSampleForWorldY(double worldY) {
    if (_roadSpansByRow.isEmpty || _layout.rows <= 0) {
      return null;
    }

    final wrappedWorldY = ((worldY % gridHeight) + gridHeight) % gridHeight;
    final centerRow = wrappedWorldY / cellSize;
    double weightedStart = 0.0;
    double weightedEnd = 0.0;
    double totalWeight = 0.0;

    for (var offset = -2; offset <= 2; offset++) {
      final rawSampleRow = (centerRow + offset).round();
      final sampleRow = _wrapRow(rawSampleRow);
      final span = _roadSpanForRow(sampleRow);
      if (span == null) {
        continue;
      }

      final distance = math.min(
        (centerRow - rawSampleRow).abs(),
        _layout.rows.toDouble() - (centerRow - rawSampleRow).abs(),
      );
      final weight = math.max(0.0, 1.0 - (distance / 2.5));
      if (weight <= 0) {
        continue;
      }

      weightedStart += span.startColumn * weight;
      weightedEnd += span.endColumn * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) {
      return null;
    }

    return _RoadSample(
      startColumn: weightedStart / totalWeight,
      endColumn: weightedEnd / totalWeight,
    );
  }

  StageRoadSpan? _roadSpanForRow(int row) {
    final wrappedRow = _wrapRow(row);
    final exact = _roadSpansByRow[wrappedRow];
    if (exact != null) {
      return exact;
    }

    for (var offset = 1; offset < _layout.rows; offset++) {
      final forward = _roadSpansByRow[_wrapRow(wrappedRow + offset)];
      if (forward != null) {
        return forward;
      }
      final backward = _roadSpansByRow[_wrapRow(wrappedRow - offset)];
      if (backward != null) {
        return backward;
      }
    }

    return null;
  }

  int _wrapRow(int row) {
    if (_layout.rows <= 0) {
      return 0;
    }
    return ((row % _layout.rows) + _layout.rows) % _layout.rows;
  }
}

class _RoadSample {
  const _RoadSample({required this.startColumn, required this.endColumn});

  final double startColumn;
  final double endColumn;

  double get width => endColumn - startColumn + 1;
  double get centerColumn => (startColumn + endColumn) / 2;
}

class _StageWall {
  const _StageWall({required this.rect, required this.type});

  final Rect rect;
  final WallType type;
}

class _StageFlag {
  _StageFlag(this.position);

  final Vector2 position;
  bool collected = false;
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:initialsj/game/engine/racing_game.dart';
import 'package:initialsj/game/world/stage_layout.dart';

/// Parallax stage background.
///
/// This used to be a Flutter widget driven by a repeating [AnimationController],
/// which rebuilt a `LayoutBuilder` and an `Image` subtree 60 times a second
/// purely to force a repaint. Rendering it as a Flame component puts it on the
/// same canvas as the rest of the scene and costs no widget work at all.
class Backdrop extends PositionComponent with HasGameReference<RacingGame> {
  Backdrop({required this.stageNumber}) : super(priority: -1000);

  static const double overscanXFactor = 0.10;
  static const double overscanYFactor = 0.12;
  static const double laneShiftFactor = 0.055;
  static const double curveShiftFactor = 0.12;
  static const double progressShiftFactor = 0.10;

  final int stageNumber;

  Sprite? _sprite;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _sprite = await Sprite.load(
      StageLayout.gameplayBackgroundSpriteForStage(stageNumber),
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final sprite = _sprite;
    if (sprite == null || !game.isLoaded) {
      return;
    }

    final width = game.size.x;
    final height = game.size.y;
    final overscanX = width * overscanXFactor;
    final overscanY = height * overscanYFactor;

    final horizontalShift =
        (-game.normalizedPlayerLaneOffset * width * laneShiftFactor) -
        (game.lookaheadRoadCurve * width * curveShiftFactor);
    final verticalShift =
        (game.mapProgress.clamp(0.0, 1.0) - 0.5) * height * progressShiftFactor;

    final destination = Rect.fromLTWH(
      -overscanX + horizontalShift,
      -overscanY + verticalShift,
      width + (overscanX * 2),
      height + (overscanY * 2),
    );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height));

    // BoxFit.cover: scale to fill the destination, cropping the overflow.
    final source = sprite.srcSize;
    final coverScale = math.max(
      destination.width / source.x,
      destination.height / source.y,
    );
    sprite.renderRect(
      canvas,
      Rect.fromCenter(
        center: destination.center,
        width: source.x * coverScale,
        height: source.y * coverScale,
      ),
    );

    canvas.restore();
  }
}

import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/racing_game.dart';

class Chaser extends SpriteComponent with HasGameReference<RacingGame> {
  Chaser(this.spawnPoint)
    : worldPosition = spawnPoint.clone(),
      super(size: Vector2.all(64), anchor: Anchor.center);

  static const double moveSpeed = 300.0;
  static const double rotationLerpSpeed = 8.0;
  static const double widthToCellFactor = 0.76;
  static const double spriteAspectRatio = 1440 / 969;
  static const double collisionWidthFactor = 0.45;
  static const double collisionHeightFactor = 0.62;
  static const double baseRenderWidthFactor = 0.18;

  /// Parked well outside the viewport when the chaser is too far to be drawn.
  static const double _offscreenPosition = -10000;

  final Vector2 spawnPoint;
  Vector2 worldPosition;
  Vector2 collisionSize = Vector2.all(64);

  @override
  Future<void> onLoad() async {
    sprite = await Sprite.load('vehicles/vehicle_police_car.webp');
    syncSizeToStage();
    await super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);
    syncSizeToStage();

    // Chasers hold position during the countdown, but still have to be placed
    // on screen or they would render at the world origin.
    if (!game.isCountingDown) {
      final toPlayer = game.playerWorldPosition - worldPosition;
      if (toPlayer.length2 > 0) {
        final direction = toPlayer.normalized();
        _moveAlongAxis(Vector2(direction.x * moveSpeed * dt, 0));
        _moveAlongAxis(Vector2(0, direction.y * moveSpeed * dt));
        _updateRotation(direction, dt);
      }
    }

    if (!game.isWithinPseudoView(worldPosition.y)) {
      position = Vector2(_offscreenPosition, _offscreenPosition);
      return;
    }

    final projected = game.projectWorldPosition(worldPosition);
    final scale = game.perspectiveScaleForWorldY(worldPosition.y);
    final renderWidth = (game.size.x * baseRenderWidthFactor) * scale;
    size = Vector2(renderWidth, renderWidth * spriteAspectRatio);
    position = Vector2(projected.dx, projected.dy);
    priority = projected.dy.round();
  }

  void syncSizeToStage() {
    final width = game.stage.cellSize * widthToCellFactor;
    collisionSize = Vector2(width, width * spriteAspectRatio);
  }

  void resetToSpawn() {
    worldPosition.setFrom(spawnPoint);
    angle = 0;
  }

  Rect get collisionRect => Rect.fromCenter(
    center: Offset(worldPosition.x, worldPosition.y),
    width: collisionSize.x * collisionWidthFactor,
    height: collisionSize.y * collisionHeightFactor,
  );

  void _moveAlongAxis(Vector2 delta) {
    if (delta.length2 == 0) {
      return;
    }

    final next = game.stage.clampToRoad(worldPosition + delta, collisionSize);
    final hitbox = Rect.fromCenter(
      center: Offset(next.x, next.y),
      width: collisionSize.x * collisionWidthFactor,
      height: collisionSize.y * collisionHeightFactor,
    );
    if (!game.stage.collidesWithWall(hitbox)) {
      worldPosition.setFrom(next);
    }
  }

  void _updateRotation(Vector2 direction, double dt) {
    final targetAngle = math.atan2(direction.y, direction.x) + (math.pi / 2);
    final delta = ((targetAngle - angle + math.pi) % (2 * math.pi)) - math.pi;
    angle += delta * math.min(1, dt * rotationLerpSpeed);
  }
}

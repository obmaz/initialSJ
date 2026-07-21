import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/camera_centered_game.dart';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';

class CameraCenteredPlayer extends SpriteComponent
    with HasGameReference<CameraCenteredGame> {
  static const double collisionWidthFactor = 0.34;
  static const double collisionHeightFactor = 0.5;
  static const double steeringLerpSpeed = 8.0;
  static const double maxSteeringAngle = 0.54;
  static const double widthToCellFactor = 3.0;
  static const double nitroBoostPerInterval = 50.0;
  static const double speedDisplayFactor = 2.8;
  static const double roadScrollFactor = 4.0;
  static const double collisionSpeedRetainFactor = 0.56;
  static const double collisionBounceFactor = 0.6;
  static const double collisionLateralNudgeFactor = 0.28;
  static const double collisionForwardNudgeFactor = 0.12;
  static const double analogSteeringAccelerationFactor = 0.9;
  static const int renderPriority = 1000;

  CameraCenteredPlayer({required this.vehicle})
    : super(
        size: Vector2.all(64),
        anchor: Anchor.bottomCenter,
        priority: renderPriority,
      );

  final VehicleSpec vehicle;

  Vector2 collisionSize = Vector2.all(64);
  bool movingLeft = false;
  bool movingRight = false;
  bool movingUp = false;
  bool movingDown = false;
  double currentSpeed = 0.0;
  Vector2 worldPosition = Vector2.zero();
  final Vector2 _velocity = Vector2.zero();
  double _spriteAspectRatio = 1402 / 1122;
  double _steeringInput = 0.0;

  @override
  Future<void> onLoad() async {
    sprite = await Sprite.load(vehicle.assetName);
    final spriteSourceSize = sprite?.srcSize;
    if (spriteSourceSize != null && spriteSourceSize.y != 0) {
      _spriteAspectRatio = spriteSourceSize.x / spriteSourceSize.y;
    }
    if (vehicle.tintColorValue != 0xFFFFFFFF) {
      paint = Paint()
        ..colorFilter = ColorFilter.mode(
          Color(vehicle.tintColorValue).withValues(alpha: 0.92),
          BlendMode.modulate,
        );
    }
    syncSizeToStage();
    await super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);

    final input = Vector2.zero();
    if (movingLeft) {
      input.x -= 1;
    }
    if (movingRight) {
      input.x += 1;
    }
    if (movingUp) {
      input.y -= 1;
    }
    if (movingDown) {
      input.y += 1;
    }

    if (input.length2 > 0) {
      input.normalize();
      _applyDirectionalAcceleration(input, dt);
    } else {
      _applyIdleDrag(dt);
    }
    _syncCurrentSpeed();
    _updateSteeringVisual(dt);

    _moveAlongAxis(
      Vector2(_velocity.x * dt * speedDisplayFactor * roadScrollFactor, 0),
    );
    _moveAlongAxis(
      Vector2(0, _velocity.y * dt * speedDisplayFactor * roadScrollFactor),
    );
    position = game.playerRenderPosition;
  }

  void syncSizeToStage() {
    final width = game.stage.cellSize * widthToCellFactor;
    collisionSize = Vector2(width, width * _spriteAspectRatio);
    final renderWidth =
        (game.size.x / CameraCenteredGame.targetVisibleStageCells) *
        widthToCellFactor;
    size = Vector2(renderWidth, renderWidth * _spriteAspectRatio);
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(0, size.y * 0.24);

    final shadowRect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y - (size.y * 0.015)),
      width: size.x * 0.66,
      height: size.y * 0.12,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = const Color(0xAA05060B)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    super.render(canvas);
    canvas.restore();
  }

  void handleCommand(GameplayCommand command) {
    switch (command.type) {
      case GameplayCommandType.moveLeft:
        movingLeft = command.state != CommandState.stop;
        break;
      case GameplayCommandType.moveRight:
        movingRight = command.state != CommandState.stop;
        break;
      case GameplayCommandType.accelerate:
        movingUp = command.state != CommandState.stop;
        break;
      case GameplayCommandType.brake:
        movingDown = command.state != CommandState.stop;
        break;
      case GameplayCommandType.nitro:
        if (command.state == CommandState.start) {
          applyNitroBurst();
        }
        break;
      default:
        break;
    }
  }

  void applyNitroBurst() {
    final direction = _driveDirection();
    final boostedSpeed = currentSpeed + nitroBoostPerInterval;
    _velocity
      ..setFrom(direction)
      ..scale(boostedSpeed / speedDisplayFactor);
    _syncCurrentSpeed();
  }

  void resetMotion() {
    _velocity.setZero();
    currentSpeed = 0;
    angle = 0;
    movingLeft = false;
    movingRight = false;
    movingUp = false;
    movingDown = false;
    _steeringInput = 0;
  }

  void setSteeringInput(double value) {
    _steeringInput = value.clamp(-1.0, 1.0);
  }

  void _applyDirectionalAcceleration(Vector2 input, double dt) {
    final previousSpeed = currentSpeed;
    if (_velocity.length2 > 0) {
      final alignment = _velocity.normalized().dot(input);
      if (alignment < 0.98) {
        final penalty = ((1 - alignment) / 2).clamp(0.0, 1.0);
        final friction = (1 - (penalty * vehicle.turnFriction * dt)).clamp(
          0.35,
          1.0,
        );
        _velocity.scale(friction);
      }
    }

    _velocity.add(input * vehicle.acceleration * dt);
    _syncCurrentSpeed();
    final speed = currentSpeed;
    if (speed > maxSpeed) {
      final allowedSpeed = previousSpeed > maxSpeed ? previousSpeed : maxSpeed;
      if (speed > allowedSpeed) {
        _velocity.scale(allowedSpeed / speed);
        _syncCurrentSpeed();
      }
    }

    if (_steeringInput != 0) {
      _velocity.x +=
          _steeringInput *
          vehicle.acceleration *
          analogSteeringAccelerationFactor *
          dt;
      _syncCurrentSpeed();
      if (currentSpeed > maxSpeed && previousSpeed <= maxSpeed) {
        _velocity.scale(maxSpeed / currentSpeed);
        _syncCurrentSpeed();
      }
      if (currentSpeed > previousSpeed && previousSpeed > maxSpeed) {
        _velocity.scale(previousSpeed / currentSpeed);
        _syncCurrentSpeed();
      }
    }
  }

  void _applyIdleDrag(double dt) {
    if (_velocity.length2 == 0) {
      return;
    }
    final nextSpeed = math.max(0, _velocity.length - (vehicle.idleDrag * dt));
    if (nextSpeed == 0) {
      _velocity.setZero();
      return;
    }
    _velocity.scale(nextSpeed / _velocity.length);
    _syncCurrentSpeed();
  }

  void _moveAlongAxis(Vector2 delta) {
    if (delta.length2 == 0) {
      return;
    }

    final candidate = worldPosition + delta;
    final shouldWrapForward =
        delta.y < 0 &&
        candidate.y < (game.stage.gridTop + (collisionSize.y / 2));
    final wrappedCandidate = shouldWrapForward
        ? Vector2(candidate.x, candidate.y + game.stage.gridHeight)
        : candidate;
    final next = game.stage.clampToRoad(wrappedCandidate, collisionSize);
    final hitbox = Rect.fromCenter(
      center: Offset(next.x, next.y),
      width: collisionSize.x * collisionWidthFactor,
      height: collisionSize.y * collisionHeightFactor,
    );
    if (!game.stage.collidesWithWall(hitbox)) {
      worldPosition.setFrom(next);
      game.playerWorldPosition = worldPosition.clone();
      if (shouldWrapForward) {
        game.handleLapAdvance();
      }
      return;
    }

    if (delta.x != 0) {
      _velocity.x = -_velocity.x * collisionBounceFactor;
      final forwardCarry = math.max(
        vehicle.acceleration * 0.12,
        _velocity.length * collisionSpeedRetainFactor,
      );
      _velocity.y = -forwardCarry;
      final nudged = game.stage.clampToRoad(
        worldPosition +
            Vector2(
              delta.x.sign * -collisionSize.x * collisionLateralNudgeFactor,
              -collisionSize.y * collisionForwardNudgeFactor,
            ),
        collisionSize,
      );
      worldPosition.setFrom(nudged);
    }
    if (delta.y != 0) {
      final forwardCarry = math.max(
        vehicle.acceleration * 0.08,
        _velocity.length * (collisionSpeedRetainFactor * 0.48),
      );
      _velocity.y = -forwardCarry;
      _velocity.x *= 0.72;
      final lateralNudge = movingLeft
          ? collisionSize.x * collisionLateralNudgeFactor
          : movingRight
          ? -collisionSize.x * collisionLateralNudgeFactor
          : (worldPosition.x >=
                    game.stage.roadCenterWorldXForWorldY(worldPosition.y)
                ? -collisionSize.x * collisionLateralNudgeFactor
                : collisionSize.x * collisionLateralNudgeFactor);
      final nudged = game.stage.clampToRoad(
        worldPosition +
            Vector2(
              lateralNudge,
              -collisionSize.y * (collisionForwardNudgeFactor * 0.7),
            ),
        collisionSize,
      );
      worldPosition.setFrom(nudged);
    }
    _syncCurrentSpeed();
    game.playerWorldPosition = worldPosition.clone();
  }

  void _updateSteeringVisual(double dt) {
    var steer = _steeringInput * maxSteeringAngle;
    if (steer == 0.0) {
      if (movingLeft && !movingRight) {
        steer = -maxSteeringAngle * 0.75;
      } else if (movingRight && !movingLeft) {
        steer = maxSteeringAngle * 0.75;
      }
    }

    final delta = steer - angle;
    angle += delta * math.min(1, dt * steeringLerpSpeed);
  }

  double get maxSpeed => vehicle.maxSpeed;

  void _syncCurrentSpeed() {
    currentSpeed = _velocity.length * speedDisplayFactor;
  }

  Vector2 _driveDirection() {
    final input = Vector2.zero();
    if (movingLeft) {
      input.x -= 1;
    }
    if (movingRight) {
      input.x += 1;
    }
    if (movingUp) {
      input.y -= 1;
    }
    if (movingDown) {
      input.y += 1;
    }
    if (input.length2 > 0) {
      input.normalize();
      return input;
    }
    if (_velocity.length2 > 0) {
      return _velocity.normalized();
    }
    return Vector2(0, -1);
  }
}

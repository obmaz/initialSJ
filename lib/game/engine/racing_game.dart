import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/game_session_controller.dart';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/game/entities/camera_centered_chaser.dart';
import 'package:initialsj/game/entities/camera_centered_player.dart';
import 'package:initialsj/game/world/camera_centered_stage.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/stage_run.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';

class CameraCenteredGame extends FlameGame {
  static const int totalLapCount = 2;
  static const int stageBlockDistanceMeters = 8;
  CameraCenteredGame({
    required this.sessionController,
    required this.stageNumber,
    required this.vehicle,
  });

  static const double stateUpdateInterval = 0.1;
  static const int initialLives = 3;
  static const double maxFuel = 1.0;
  static const double fuelDrainPerSpeedUnit = 0.000055;
  static const double nitroFuelDrainMultiplier = 2.4;
  static const double collisionCooldownSeconds = 1.2;
  static const double playerAnchorYFactor = 0.86;
  static const double horizonYFactor = 0.66;
  static const double roadBottomHalfWidthFactor = 0.95;
  static const double roadTopHalfWidthFactor = 0.025;
  static const double roadCurveResponseFactor = 1.25;
  static const double visibleDepthInCells = 15.6;
  static const double depthCompressionPower = 1.0;
  static const double roadWidthCompressionPower = 0.58;
  static const double targetVisibleStageCells = 12.0;

  final GameSessionController sessionController;
  final int stageNumber;
  final VehicleSpec vehicle;

  late final CameraCenteredStage stage;
  late final CameraCenteredPlayer player;
  final List<CameraCenteredChaser> _chasers = <CameraCenteredChaser>[];
  late Vector2 playerWorldPosition;

  var _flagsCollected = 0;
  var _currentLap = 1;
  var _livesRemaining = initialLives;
  var _collisionCount = 0;
  var _reportedOutcome = false;
  double _fuelRemaining = maxFuel;
  double _elapsed = 0.0;
  double _stateAccumulator = 0.0;
  double _collisionCooldown = 0.0;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  FutureOr<void> onLoad() async {
    stage = CameraCenteredStage();
    await add(stage);

    playerWorldPosition = stage.playerSpawnPoint.clone();

    player = CameraCenteredPlayer(vehicle: vehicle)
      ..worldPosition = playerWorldPosition;
    await add(player);

    for (final spawn in stage.chaserSpawnPoints) {
      final chaser = CameraCenteredChaser(spawn);
      _chasers.add(chaser);
      await add(chaser);
    }

    _syncPlayerAnchor();

    sessionController.commandStream.listen(_handleCommand);
    _emitStateUpdate();

    return super.onLoad();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _syncPlayerAnchor();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) {
      return;
    }

    _syncPlayerAnchor();

    _elapsed += dt;
    _stateAccumulator += dt;
    _collisionCooldown = (_collisionCooldown - dt).clamp(
      0.0,
      collisionCooldownSeconds,
    );
    _updateFuel(dt);
    _collectFlags();
    _checkChaserCollision();

    if (_stateAccumulator >= stateUpdateInterval) {
      _emitStateUpdate();
      _stateAccumulator = 0.0;
    }

    _reportOutcomeIfNeeded();
  }

  void _handleCommand(GameplayCommand command) {
    if (command.type == GameplayCommandType.pause ||
        command.type == GameplayCommandType.resume) {
      return;
    }
    player.handleCommand(command);
  }

  void _collectFlags() {
    final gained = stage.collectFlags(
      Rect.fromCenter(
        center: Offset(playerWorldPosition.x, playerWorldPosition.y),
        width: player.collisionSize.x * 0.7,
        height: player.collisionSize.y * 0.7,
      ),
    );
    if (gained > 0) {
      _flagsCollected += gained;
      _fuelRemaining = maxFuel;
    }
  }

  void _updateFuel(double dt) {
    if (player.currentSpeed <= 0 || _fuelRemaining <= 0) {
      return;
    }
    final drain =
        player.currentSpeed *
        fuelDrainPerSpeedUnit *
        vehicle.fuelDrainMultiplier *
        dt;
    _fuelRemaining = (_fuelRemaining - drain).clamp(0.0, maxFuel);
  }

  void _emitStateUpdate() {
    final status = _livesRemaining <= 0
        ? RunStatus.failed
        : _fuelRemaining <= 0
        ? RunStatus.failed
        : _currentLap > totalLapCount
        ? RunStatus.cleared
        : RunStatus.running;

    final nearbyChasers = _chasers
        .where(
          (chaser) => (chaser.worldPosition - playerWorldPosition).length < 220,
        )
        .length;

    final lapDistanceMeters =
        (stage.gridHeight / stage.cellSize).round() * stageBlockDistanceMeters;
    final remainingLapMeters =
        ((1 - stage.progressFor(playerWorldPosition)) * lapDistanceMeters)
            .ceil()
            .clamp(0, lapDistanceMeters);

    sessionController.updateState(
      StageRun(
        runId: 'camera-centered-run',
        stageNumber: stageNumber,
        livesRemaining: _livesRemaining,
        status: status,
        score: _flagsCollected * 100 - (_collisionCount * 200),
        mapProgress: stage.progressFor(playerWorldPosition),
        currentLap: _currentLap.clamp(1, totalLapCount),
        totalLaps: totalLapCount,
        lapRemainingMeters: remainingLapMeters,
        flagsCollected: _flagsCollected,
        totalFlags: stage.totalFlags,
        currentSpeed: player.currentSpeed,
        fuelRemaining: _fuelRemaining,
        playerPosition: Offset2(playerWorldPosition.x, playerWorldPosition.y),
        elapsedTime: _elapsed,
        collisionCount: _collisionCount,
        chasersNearby: nearbyChasers,
      ),
    );
  }

  void _reportOutcomeIfNeeded() {
    if (_reportedOutcome) {
      return;
    }
    if (_fuelRemaining <= 0) {
      _reportedOutcome = true;
      sessionController.reportOutcome(RunOutcome.failed);
      return;
    }
    if (_livesRemaining <= 0) {
      _reportedOutcome = true;
      sessionController.reportOutcome(RunOutcome.failed);
      return;
    }
    if (_currentLap > totalLapCount) {
      _reportedOutcome = true;
      sessionController.reportOutcome(RunOutcome.cleared);
    }
  }

  void handleLapAdvance() {
    if (_reportedOutcome) {
      return;
    }
    _currentLap += 1;
  }

  Vector2 get playerScreenAnchor =>
      Vector2(size.x / 2, size.y * playerAnchorYFactor);
  Vector2 get playerRenderPosition {
    final lateralTravel =
        roadHalfWidthForWorldY(playerWorldPosition.y) *
        normalizedPlayerLaneOffset *
        0.92;
    return Vector2(playerScreenAnchor.x + lateralTravel, playerScreenAnchor.y);
  }

  double get horizonY => size.y * horizonYFactor;
  double get visibleDepth => stage.cellSize * visibleDepthInCells;

  Rect get viewportInWorld => Rect.fromCenter(
    center: Offset(playerWorldPosition.x, playerWorldPosition.y),
    width: size.x,
    height: size.y,
  );

  Size get stageWorldSize => Size(stage.gridWidth, stage.gridHeight);
  List<String> get miniMapRows => stage.miniMapRows;
  List<Vector2> get remainingFlagPositions => stage.remainingFlagPositions;
  List<Vector2> get chaserWorldPositions => _chasers
      .map((chaser) => chaser.worldPosition.clone())
      .toList(growable: false);
  double get mapProgress => stage.progressFor(playerWorldPosition);
  double get normalizedStageX {
    final stageWidth = stage.gridWidth;
    if (stageWidth <= 0) {
      return 0.5;
    }
    return (playerWorldPosition.x / stageWidth).clamp(0.0, 1.0);
  }

  double get normalizedPlayerLaneOffset {
    final playerRoadCenterX = stage.roadCenterWorldXForWorldY(
      playerWorldPosition.y,
    );
    final playerRoadWidth = stage.roadWidthWorldForWorldY(
      playerWorldPosition.y,
    );
    if (playerRoadWidth <= 0) {
      return 0.0;
    }
    return ((playerWorldPosition.x - playerRoadCenterX) / (playerRoadWidth / 2))
        .clamp(-1.0, 1.0);
  }

  Vector2 get worldRenderOffset => playerScreenAnchor - playerWorldPosition;

  bool isWithinPseudoView(double worldY) {
    final depth = playerWorldPosition.y - worldY;
    return depth >= 0 && depth <= visibleDepth;
  }

  double normalizedDepthForWorldY(double worldY) {
    if (visibleDepth <= 0) {
      return 1.0;
    }
    final depth = playerWorldPosition.y - worldY;
    return (depth / visibleDepth).clamp(0.0, 1.0);
  }

  double perspectiveScaleForWorldY(double worldY) {
    final t = perspectiveWidthTForWorldY(worldY);
    final nearScale = (size.x / targetVisibleStageCells) / stage.cellSize;
    final farScale =
        nearScale * (roadTopHalfWidthFactor / roadBottomHalfWidthFactor);
    return lerpDouble(nearScale, farScale, t)!;
  }

  double perspectiveWidthTForWorldY(double worldY) {
    final t = normalizedDepthForWorldY(worldY);
    return math.pow(t, roadWidthCompressionPower).toDouble().clamp(0.0, 1.0);
  }

  double screenYForWorldY(double worldY) {
    final t = normalizedDepthForWorldY(worldY);
    final compressedT = math
        .pow(t, depthCompressionPower)
        .toDouble()
        .clamp(0.0, 1.0);
    return lerpDouble(playerScreenAnchor.y, horizonY, compressedT)!;
  }

  double roadCenterXForWorldY(double worldY) {
    final depth = normalizedDepthForWorldY(worldY);
    final currentRoadCenterRatio = stage.roadCenterRatioForWorldY(
      playerWorldPosition.y,
    );
    final targetRoadCenterRatio = stage.roadCenterRatioForWorldY(worldY);
    final curveDelta = (targetRoadCenterRatio - currentRoadCenterRatio) * 2;
    final curveResponse = lerpDouble(
      0.04,
      0.58,
      Curves.easeOutCubic.transform(depth),
    )!;
    final curveOffset =
        curveDelta * size.x * roadCurveResponseFactor * curveResponse;
    return playerScreenAnchor.x +
        curveOffset -
        cameraLateralOffsetForWorldY(worldY);
  }

  double roadHalfWidthForWorldY(double worldY) {
    final t = perspectiveWidthTForWorldY(worldY);
    final mapWidthRatio = stage.roadWidthRatioForWorldY(worldY);
    final totalStageColumns = stage.gridWidth / stage.cellSize;
    final roadCellCount = mapWidthRatio * totalStageColumns;
    final nearHalfWidth =
        (size.x / targetVisibleStageCells) * roadCellCount / 2;
    final farHalfWidth =
        nearHalfWidth * (roadTopHalfWidthFactor / roadBottomHalfWidthFactor);
    return lerpDouble(nearHalfWidth, farHalfWidth, t)!;
  }

  Offset projectWorldPosition(Vector2 worldPosition) {
    final roadCenterRatio = stage.roadCenterRatioForWorldY(worldPosition.y);
    final roadWidthRatio = stage.roadWidthRatioForWorldY(worldPosition.y);
    final normalizedX = ((worldPosition.x - stage.gridLeft) / stage.gridWidth)
        .clamp(0.0, 1.0);
    final relativeRoadX =
        ((normalizedX - roadCenterRatio) / (roadWidthRatio / 2)).clamp(
          -1.0,
          1.0,
        );
    final centerX = roadCenterXForWorldY(worldPosition.y);
    final halfWidth = roadHalfWidthForWorldY(worldPosition.y);
    return Offset(
      centerX + (relativeRoadX * halfWidth),
      screenYForWorldY(worldPosition.y),
    );
  }

  double cameraLateralOffsetForWorldY(double worldY) {
    final playerRoadCenterX = stage.roadCenterWorldXForWorldY(
      playerWorldPosition.y,
    );
    final playerRoadWidth = stage.roadWidthWorldForWorldY(
      playerWorldPosition.y,
    );
    if (playerRoadWidth <= 0) {
      return 0.0;
    }
    final playerLaneOffset =
        ((playerWorldPosition.x - playerRoadCenterX) / (playerRoadWidth / 2))
            .clamp(-1.0, 1.0);
    final depth = normalizedDepthForWorldY(worldY);
    final response = lerpDouble(
      0.0,
      0.16,
      Curves.easeOutExpo.transform(depth),
    )!;
    return playerLaneOffset *
        roadHalfWidthForWorldY(playerWorldPosition.y) *
        response;
  }

  void _syncPlayerAnchor() {
    player.syncSizeToStage();
    player.position = playerRenderPosition;
    player.worldPosition = playerWorldPosition;
  }

  void _checkChaserCollision() {
    if (_collisionCooldown > 0 || _livesRemaining <= 0) {
      return;
    }

    final playerHitbox = Rect.fromCenter(
      center: Offset(playerWorldPosition.x, playerWorldPosition.y),
      width: player.collisionSize.x * CameraCenteredPlayer.collisionWidthFactor,
      height:
          player.collisionSize.y * CameraCenteredPlayer.collisionHeightFactor,
    );

    final hasCollision = _chasers.any(
      (chaser) => playerHitbox.overlaps(chaser.collisionRect),
    );
    if (!hasCollision) {
      return;
    }

    _collisionCount += 1;
    _livesRemaining -= 1;
    _collisionCooldown = collisionCooldownSeconds;

    if (_livesRemaining > 0) {
      _respawnActors();
    }
  }

  void _respawnActors() {
    playerWorldPosition = stage.playerSpawnPoint.clone();
    player.resetMotion();
    for (final chaser in _chasers) {
      chaser.resetToSpawn();
    }
    _syncPlayerAnchor();
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/game_session_controller.dart';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/game/engine/run_scoring.dart';
import 'package:initialsj/game/entities/chaser.dart';
import 'package:initialsj/game/entities/player.dart';
import 'package:initialsj/game/world/backdrop.dart';
import 'package:initialsj/game/world/stage.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/stage_run.dart';
import 'package:initialsj/shared/models/vehicle_spec.dart';

class RacingGame extends FlameGame {
  static const int totalLapCount = 2;
  static const int stageBlockDistanceMeters = 8;

  RacingGame({
    required this.sessionController,
    required this.stageNumber,
    required this.vehicle,
  });

  static const double stateUpdateInterval = 0.1;
  static const double countdownSeconds = 3.0;
  static const int initialLives = 3;
  static const double maxFuel = 1.0;
  static const double fuelDrainPerSpeedUnit = 0.000055;

  /// One-shot fuel price of a nitro burst, plus how long before the next one.
  static const double nitroFuelCost = 0.08;
  static const double nitroCooldownSeconds = 1.5;

  /// Ceiling a nitro burst may push the car to, as a multiple of top speed.
  static const double nitroSpeedCapFactor = 1.35;

  static const double collisionCooldownSeconds = 1.2;
  static const double chaserNearbyWorldDistance = 220.0;
  static const double playerAnchorYFactor = 0.86;
  static const double horizonYFactor = 0.66;
  static const double roadBottomHalfWidthFactor = 0.95;
  static const double roadTopHalfWidthFactor = 0.025;
  static const double roadCurveResponseFactor = 1.25;
  static const double visibleDepthInCells = 15.6;
  static const double roadWidthCompressionPower = 0.58;
  static const double targetVisibleStageCells = 12.0;

  final GameSessionController sessionController;
  final int stageNumber;
  final VehicleSpec vehicle;

  late final Stage stage;
  late final Player player;
  final List<Chaser> _chasers = <Chaser>[];
  late Vector2 playerWorldPosition;

  StreamSubscription<GameplayCommand>? _commandSubscription;

  var _flagsCollected = 0;
  var _currentLap = 1;
  var _livesRemaining = initialLives;
  var _collisionCount = 0;
  var _reportedOutcome = false;
  double _fuelRemaining = maxFuel;
  double _elapsed = 0.0;
  double _countdownRemaining = countdownSeconds;
  double _stateAccumulator = 0.0;
  double _collisionCooldown = 0.0;
  double _nitroCooldown = 0.0;

  // Player-relative road metrics are constant for a whole frame but were being
  // recomputed by every projection call. Refreshed once per tick instead.
  double _playerRoadCenterX = 0.0;
  double _playerRoadWidth = 0.0;
  double _playerRoadCenterRatio = 0.5;
  double _playerRoadHalfWidth = 0.0;

  /// True while the pre-race countdown is running. The simulation is frozen so
  /// the HUD countdown actually means something.
  bool get isCountingDown => _countdownRemaining > 0;

  bool get isNitroReady =>
      _nitroCooldown <= 0 && _fuelRemaining >= nitroFuelCost;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  FutureOr<void> onLoad() async {
    await add(Backdrop(stageNumber: stageNumber));

    stage = Stage();
    await add(stage);

    playerWorldPosition = stage.playerSpawnPoint.clone();

    player = Player(vehicle: vehicle)..worldPosition = playerWorldPosition;
    await add(player);

    for (final spawn in stage.chaserSpawnPoints) {
      final chaser = Chaser(spawn);
      _chasers.add(chaser);
      await add(chaser);
    }

    _syncPlayerAnchor();

    _commandSubscription = sessionController.commandStream.listen(
      _handleCommand,
    );
    _emitStateUpdate();

    return super.onLoad();
  }

  @override
  void onRemove() {
    _commandSubscription?.cancel();
    _commandSubscription = null;
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    // Cell size is derived from the viewport width, so world coordinates have
    // to be rescaled or actors would teleport relative to the stage.
    final previousCellSize = isLoaded ? stage.cellSize : null;
    super.onGameResize(size);
    if (!isLoaded) {
      return;
    }

    final newCellSize = stage.cellSize;
    if (previousCellSize != null &&
        previousCellSize > 0 &&
        newCellSize > 0 &&
        newCellSize != previousCellSize) {
      final scale = newCellSize / previousCellSize;
      playerWorldPosition.scale(scale);
      for (final chaser in _chasers) {
        chaser.worldPosition.scale(scale);
      }
    }
    _syncPlayerAnchor();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isLoaded) {
      return;
    }

    _syncPlayerAnchor();
    _stateAccumulator += dt;

    if (isCountingDown) {
      _countdownRemaining = math.max(0.0, _countdownRemaining - dt);
      _emitThrottledState();
      return;
    }

    _elapsed += dt;
    _collisionCooldown = (_collisionCooldown - dt).clamp(
      0.0,
      collisionCooldownSeconds,
    );
    _nitroCooldown = (_nitroCooldown - dt).clamp(0.0, nitroCooldownSeconds);
    _updateFuel(dt);
    _collectFlags();
    _checkChaserCollision();

    _emitThrottledState();
    _reportOutcomeIfNeeded();
  }

  void _emitThrottledState() {
    if (_stateAccumulator >= stateUpdateInterval) {
      _emitStateUpdate();
      _stateAccumulator = 0.0;
    }
  }

  void _handleCommand(GameplayCommand command) {
    if (command.type == GameplayCommandType.pause ||
        command.type == GameplayCommandType.resume) {
      return;
    }
    if (isCountingDown) {
      return;
    }
    if (command.type == GameplayCommandType.nitro &&
        command.state == CommandState.start) {
      if (!isNitroReady) {
        return;
      }
      _nitroCooldown = nitroCooldownSeconds;
      _fuelRemaining = (_fuelRemaining - nitroFuelCost).clamp(0.0, maxFuel);
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

  int get currentScore => RunScoring.scoreFor(
    flagsCollected: _flagsCollected,
    collisions: _collisionCount,
  );

  void _emitStateUpdate() {
    final status = _livesRemaining <= 0 || _fuelRemaining <= 0
        ? RunStatus.failed
        : _currentLap > totalLapCount
        ? RunStatus.cleared
        : RunStatus.running;

    var nearbyChasers = 0;
    for (final chaser in _chasers) {
      if ((chaser.worldPosition - playerWorldPosition).length <
          chaserNearbyWorldDistance) {
        nearbyChasers += 1;
      }
    }

    final lapDistanceMeters =
        (stage.gridHeight / stage.cellSize).round() * stageBlockDistanceMeters;
    final remainingLapMeters =
        ((1 - stage.progressFor(playerWorldPosition)) * lapDistanceMeters)
            .ceil()
            .clamp(0, lapDistanceMeters);

    sessionController.updateState(
      StageRun(
        runId: 'stage-$stageNumber-run',
        stageNumber: stageNumber,
        livesRemaining: _livesRemaining,
        status: status,
        score: currentScore,
        mapProgress: stage.progressFor(playerWorldPosition),
        currentLap: _currentLap.clamp(1, totalLapCount),
        totalLaps: totalLapCount,
        lapRemainingMeters: remainingLapMeters,
        flagsCollected: _flagsCollected,
        totalFlags: stage.totalFlags,
        currentSpeed: player.currentSpeed,
        fuelRemaining: _fuelRemaining,
        elapsedTime: _elapsed,
        countdownRemaining: _countdownRemaining,
        nitroReady: isNitroReady,
        collisionCount: _collisionCount,
        chasersNearby: nearbyChasers,
      ),
    );
  }

  void _reportOutcomeIfNeeded() {
    if (_reportedOutcome) {
      return;
    }

    final RunOutcome? outcome;
    if (_fuelRemaining <= 0 || _livesRemaining <= 0) {
      outcome = RunOutcome.failed;
    } else if (_currentLap > totalLapCount) {
      outcome = RunOutcome.cleared;
    } else {
      outcome = null;
    }
    if (outcome == null) {
      return;
    }

    _reportedOutcome = true;
    // Flush the final state before the outcome so the result screen scores the
    // run as it actually ended, not as it looked up to 100ms earlier.
    _emitStateUpdate();
    _stateAccumulator = 0.0;
    sessionController.reportOutcome(outcome);
  }

  void handleLapAdvance() {
    if (_reportedOutcome) {
      return;
    }
    _currentLap += 1;
  }

  // Projection ----------------------------------------------------------

  Vector2 get playerScreenAnchor =>
      Vector2(size.x / 2, size.y * playerAnchorYFactor);

  Vector2 get playerRenderPosition {
    final lateralTravel =
        _playerRoadHalfWidth * normalizedPlayerLaneOffset * 0.92;
    return Vector2(playerScreenAnchor.x + lateralTravel, playerScreenAnchor.y);
  }

  double get horizonY => size.y * horizonYFactor;
  double get visibleDepth => stage.cellSize * visibleDepthInCells;

  Size get stageWorldSize => Size(stage.gridWidth, stage.gridHeight);
  List<String> get miniMapRows => stage.miniMapRows;
  List<Vector2> get remainingFlagPositions => stage.remainingFlagPositions;
  List<Vector2> get chaserWorldPositions => _chasers
      .map((chaser) => chaser.worldPosition.clone())
      .toList(growable: false);
  double get mapProgress => stage.progressFor(playerWorldPosition);

  double get normalizedPlayerLaneOffset {
    if (_playerRoadWidth <= 0) {
      return 0.0;
    }
    return ((playerWorldPosition.x - _playerRoadCenterX) /
            (_playerRoadWidth / 2))
        .clamp(-1.0, 1.0);
  }

  /// How far the road ahead curves relative to the player, in road-centre
  /// ratio units. Drives the backdrop parallax.
  double get lookaheadRoadCurve {
    final distantRatio = stage.roadCenterRatioForWorldY(
      playerWorldPosition.y - (visibleDepth * 0.7),
    );
    return (distantRatio - _playerRoadCenterRatio).clamp(-0.5, 0.5);
  }

  bool isWithinPseudoView(double worldY) {
    final depth = playerWorldPosition.y - worldY;
    return depth >= 0 && depth <= visibleDepth;
  }

  double normalizedDepthForWorldY(double worldY) {
    final depth = visibleDepth;
    if (depth <= 0) {
      return 1.0;
    }
    return ((playerWorldPosition.y - worldY) / depth).clamp(0.0, 1.0);
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

  /// Depth maps linearly to screen height; there is deliberately no extra
  /// compression curve here.
  double screenYForWorldY(double worldY) {
    return lerpDouble(
      playerScreenAnchor.y,
      horizonY,
      normalizedDepthForWorldY(worldY),
    )!;
  }

  double roadCenterXForWorldY(double worldY) {
    final depth = normalizedDepthForWorldY(worldY);
    final targetRoadCenterRatio = stage.roadCenterRatioForWorldY(worldY);
    final curveDelta = (targetRoadCenterRatio - _playerRoadCenterRatio) * 2;
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
    return Offset(
      roadCenterXForWorldY(worldPosition.y) +
          (relativeRoadX * roadHalfWidthForWorldY(worldPosition.y)),
      screenYForWorldY(worldPosition.y),
    );
  }

  double cameraLateralOffsetForWorldY(double worldY) {
    if (_playerRoadWidth <= 0) {
      return 0.0;
    }
    final response = lerpDouble(
      0.0,
      0.16,
      Curves.easeOutExpo.transform(normalizedDepthForWorldY(worldY)),
    )!;
    return normalizedPlayerLaneOffset * _playerRoadHalfWidth * response;
  }

  // Internals -----------------------------------------------------------

  void _syncPlayerAnchor() {
    _refreshPlayerRoadMetrics();
    player.syncSizeToStage();
    player.position = playerRenderPosition;
    player.worldPosition = playerWorldPosition;
  }

  void _refreshPlayerRoadMetrics() {
    final playerY = playerWorldPosition.y;
    _playerRoadCenterX = stage.roadCenterWorldXForWorldY(playerY);
    _playerRoadWidth = stage.roadWidthWorldForWorldY(playerY);
    _playerRoadCenterRatio = stage.roadCenterRatioForWorldY(playerY);
    _playerRoadHalfWidth = roadHalfWidthForWorldY(playerY);
  }

  void _checkChaserCollision() {
    if (_collisionCooldown > 0 || _livesRemaining <= 0) {
      return;
    }

    final playerHitbox = Rect.fromCenter(
      center: Offset(playerWorldPosition.x, playerWorldPosition.y),
      width: player.collisionSize.x * Player.collisionWidthFactor,
      height: player.collisionSize.y * Player.collisionHeightFactor,
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

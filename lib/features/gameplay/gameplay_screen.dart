import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:initialsj/app/router/app_router.dart';
import 'package:initialsj/features/gameplay/widgets/pause_overlay.dart';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/game/engine/game_session_controller.dart';
import 'package:initialsj/game/engine/racing_game.dart';
import 'package:initialsj/game/engine/run_scoring.dart';
import 'package:initialsj/game/hud/gameplay_hud_overlay.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/stage_run.dart';
import 'package:initialsj/shared/state/app_state_controller.dart';

class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key});

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen> {
  late final GameSessionController _sessionController;
  late final RacingGame _game;
  final ValueNotifier<StageRun?> _runNotifier = ValueNotifier<StageRun?>(null);
  bool _isPaused = false;
  StreamSubscription<GameplayCommand>? _commandSubscription;
  StreamSubscription<StageRun>? _stateSubscription;
  StreamSubscription<RunOutcome>? _outcomeSubscription;
  int _joystickHorizontal = 0;
  double _joystickSteering = 0.0;

  @override
  void initState() {
    super.initState();
    _sessionController = GameSessionController();
    final appState = context.read<AppStateController>();
    _game = RacingGame(
      sessionController: _sessionController,
      stageNumber: appState.activeRun?.stageNumber ?? 1,
      vehicle: appState.selectedVehicle,
    );

    _commandSubscription = _sessionController.commandStream.listen((command) {
      if (command.type == GameplayCommandType.pause) {
        setState(() => _isPaused = true);
        _game.pauseEngine();
      } else if (command.type == GameplayCommandType.resume) {
        setState(() => _isPaused = false);
        _game.resumeEngine();
      }
    });

    _stateSubscription = _sessionController.stateStream.listen((runState) {
      if (!mounted) {
        return;
      }
      _runNotifier.value = runState;
      context.read<AppStateController>().updateActiveRun(runState);
    });

    _outcomeSubscription = _sessionController.outcomeStream.listen(
      _handleOutcome,
    );
  }

  void _handleOutcome(RunOutcome outcome) {
    if (!mounted) {
      return;
    }
    final appState = context.read<AppStateController>();
    final run = appState.activeRun;

    final score = run?.score ?? 0;
    final summary = ResultSummary(
      finalScore: score,
      stageNumber: run?.stageNumber ?? _game.stageNumber,
      outcome: outcome,
      flagsCollected: run?.flagsCollected ?? 0,
      coinsAwarded: RunScoring.coinsFor(score: score, outcome: outcome),
      newBestScore: score > appState.profile.bestScore,
      clearTimeSeconds: run?.elapsedTime ?? 0,
      lapsCompleted: run == null
          ? 0
          : run.currentLap > run.totalLaps
          ? run.totalLaps
          : run.currentLap,
    );

    if (run != null) {
      appState.updateActiveRun(
        run.copyWith(
          status: outcome == RunOutcome.cleared
              ? RunStatus.cleared
              : RunStatus.failed,
        ),
      );
    }
    appState.setLatestResult(summary);
    unawaited(appState.checkNewBestScore(summary.finalScore));
    unawaited(appState.addCoins(summary.coinsAwarded));
    context.go(AppRouter.resultPath);
  }

  void _releaseGameplayInputs() {
    _updateJoystickDirection(0, 0);
    _updateJoystickSteering(0);
    _sessionController.accelerate(CommandState.stop);
    _sessionController.brake(CommandState.stop);
    _sessionController.moveLeft(CommandState.stop);
    _sessionController.moveRight(CommandState.stop);
  }

  @override
  void deactivate() {
    _releaseGameplayInputs();
    super.deactivate();
  }

  @override
  void dispose() {
    _commandSubscription?.cancel();
    _stateSubscription?.cancel();
    _outcomeSubscription?.cancel();
    _sessionController.dispose();
    _runNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeBottom = mediaQuery.padding.bottom;
    final controlsHeight =
        (mediaQuery.size.height * 0.21).clamp(140.0, 196.0) + safeBottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.read<AppStateController>().endRun();
        context.go(AppRouter.titlePath);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Main gameplay area. The stage backdrop is drawn by the engine
            // itself, so no Flutter background builder is needed here.
            Positioned.fill(
              child: GameWidget(
                game: _game,
                overlayBuilderMap: {
                  'hud': (context, game) => GameplayHudOverlay(
                    sessionController: _sessionController,
                    game: _game,
                  ),
                },
                initialActiveOverlays: const ['hud'],
              ),
            ),

            // Touch controls (bottom area)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: controlsHeight,
              child: SafeArea(top: false, child: _buildControls(context)),
            ),

            // Pause overlay
            if (_isPaused)
              Positioned.fill(
                child: PauseOverlay(sessionController: _sessionController),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final verticalPadding = safeBottom > 0 ? 2.0 : 6.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(4, verticalPadding, 24, verticalPadding),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: ValueListenableBuilder<StageRun?>(
              valueListenable: _runNotifier,
              builder: (context, run, _) => _ActionButton(
                assetPath: 'assets/images/ui/nitro_button.webp',
                enabled: run?.nitroReady ?? true,
                onPressed: () => _sessionController.nitro(CommandState.start),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 92,
            height: 92,
            child: _ActionButton(
              assetPath: 'assets/images/ui/skill_button.webp',
              label: 'BRAKE',
              onPressed: () => _sessionController.brake(CommandState.start),
              onReleased: () => _sessionController.brake(CommandState.stop),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Align(
              alignment: const Alignment(-0.35, 0),
              child: _VirtualJoystick(
                onDirectionChanged: _updateJoystickDirection,
                onSteeringChanged: _updateJoystickSteering,
                onTouchActiveChanged: (active) {
                  _sessionController.accelerate(
                    active ? CommandState.start : CommandState.stop,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateJoystickDirection(int horizontal, int vertical) {
    if (_joystickHorizontal == horizontal) {
      return;
    }

    if (_joystickHorizontal == -1) {
      _sessionController.moveLeft(CommandState.stop);
    } else if (_joystickHorizontal == 1) {
      _sessionController.moveRight(CommandState.stop);
    }

    _joystickHorizontal = horizontal;

    if (_joystickHorizontal == -1) {
      _sessionController.moveLeft(CommandState.start);
    } else if (_joystickHorizontal == 1) {
      _sessionController.moveRight(CommandState.start);
    }
  }

  void _updateJoystickSteering(double steering) {
    if ((_joystickSteering - steering).abs() < 0.001) {
      return;
    }
    _joystickSteering = steering;
    // Routed through the session controller rather than touching the engine
    // directly, so input sent before the game finishes loading is harmless.
    _sessionController.steer(steering);
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.assetPath,
    required this.onPressed,
    this.onReleased,
    this.label,
    this.enabled = true,
  });

  final String assetPath;
  final VoidCallback onPressed;
  final VoidCallback? onReleased;
  final String? label;
  final bool enabled;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;

    return Listener(
      onPointerDown: (_) {
        if (!widget.enabled) {
          return;
        }
        setState(() => _pressed = true);
        widget.onPressed();
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 90),
        scale: _pressed ? 0.95 : 1.0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 90),
          opacity: widget.enabled ? (_pressed ? 0.92 : 1.0) : 0.4,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              Image.asset(widget.assetPath),
              if (label != null)
                Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _release() {
    if (_pressed) {
      setState(() => _pressed = false);
    }
    widget.onReleased?.call();
  }
}

class _VirtualJoystick extends StatefulWidget {
  const _VirtualJoystick({
    required this.onDirectionChanged,
    required this.onSteeringChanged,
    required this.onTouchActiveChanged,
  });

  final void Function(int horizontal, int vertical) onDirectionChanged;
  final ValueChanged<double> onSteeringChanged;
  final ValueChanged<bool> onTouchActiveChanged;

  @override
  State<_VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<_VirtualJoystick> {
  static const double _baseSize = 124;
  static const double _knobSize = 50;
  static const double _travelRadius = 34;
  static const double _deadZone = 10;

  Offset _dragOffset = Offset.zero;
  bool _touchActive = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _baseSize,
      height: _baseSize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _beginTouch(details.localPosition),
        onTapUp: (_) => _resetStick(),
        onTapCancel: _resetStick,
        onPanStart: (details) => _beginTouch(details.localPosition),
        onPanUpdate: (details) =>
            _updateFromLocalPosition(details.localPosition),
        onPanEnd: (_) => _resetStick(),
        onPanCancel: _resetStick,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white38, width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
              Transform.translate(
                offset: _dragOffset,
                child: Container(
                  width: _knobSize,
                  height: _knobSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE33B2F),
                    border: Border.all(color: Colors.white70, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A plain tap counts as "hold the throttle", so the player does not have to
  /// drag before the car will move.
  void _beginTouch(Offset localPosition) {
    if (!_touchActive) {
      _touchActive = true;
      widget.onTouchActiveChanged(true);
    }
    _updateFromLocalPosition(localPosition);
  }

  void _updateFromLocalPosition(Offset localPosition) {
    const center = Offset(_baseSize / 2, _baseSize / 2);
    final rawDelta = localPosition - center;
    final delta = Offset(rawDelta.dx.clamp(-_travelRadius, _travelRadius), 0);

    setState(() {
      _dragOffset = delta;
    });

    final horizontal = delta.dx > _deadZone
        ? 1
        : delta.dx < -_deadZone
        ? -1
        : 0;
    final steering = (delta.dx / _travelRadius).clamp(-1.0, 1.0);
    widget.onDirectionChanged(horizontal, 0);
    widget.onSteeringChanged(steering);
  }

  void _resetStick() {
    setState(() {
      _dragOffset = Offset.zero;
    });
    if (_touchActive) {
      _touchActive = false;
      widget.onTouchActiveChanged(false);
    }
    widget.onDirectionChanged(0, 0);
    widget.onSteeringChanged(0);
  }
}

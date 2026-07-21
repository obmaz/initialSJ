import 'dart:async';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/models/stage_run.dart';

class GameSessionController {
  // Broadcasters
  final StreamController<GameplayCommand> _commandStreamController =
      StreamController<GameplayCommand>.broadcast();
  final StreamController<StageRun> _stateStreamController =
      StreamController<StageRun>.broadcast();
  final StreamController<RunOutcome> _outcomeStreamController =
      StreamController<RunOutcome>.broadcast();

  Stream<GameplayCommand> get commandStream => _commandStreamController.stream;
  Stream<StageRun> get stateStream => _stateStreamController.stream;
  Stream<RunOutcome> get outcomeStream => _outcomeStreamController.stream;

  // Command Input
  void sendCommand(GameplayCommand command) {
    if (_commandStreamController.isClosed) {
      return;
    }
    _commandStreamController.add(command);
  }

  // State Update (called by Flame Engine)
  void updateState(StageRun updatedRun) {
    if (_stateStreamController.isClosed) {
      return;
    }
    _stateStreamController.add(updatedRun);
  }

  void reportOutcome(RunOutcome outcome) {
    if (_outcomeStreamController.isClosed) {
      return;
    }
    _outcomeStreamController.add(outcome);
  }

  void dispose() {
    _commandStreamController.close();
    _stateStreamController.close();
    _outcomeStreamController.close();
  }

  // Common Command Helpers
  void moveLeft(CommandState state) =>
      sendCommand(GameplayCommand(GameplayCommandType.moveLeft, state: state));

  void moveRight(CommandState state) =>
      sendCommand(GameplayCommand(GameplayCommandType.moveRight, state: state));

  /// Analog steering axis in [-1, 1]. Routed through the command stream so the
  /// UI never reaches into the engine directly.
  void steer(double value) =>
      sendCommand(GameplayCommand(GameplayCommandType.steer, value: value));

  void accelerate(CommandState state) => sendCommand(
    GameplayCommand(GameplayCommandType.accelerate, state: state),
  );

  void brake(CommandState state) =>
      sendCommand(GameplayCommand(GameplayCommandType.brake, state: state));

  void nitro(CommandState state) =>
      sendCommand(GameplayCommand(GameplayCommandType.nitro, state: state));

  void pause() => sendCommand(const GameplayCommand(GameplayCommandType.pause));

  void resume() =>
      sendCommand(const GameplayCommand(GameplayCommandType.resume));
}

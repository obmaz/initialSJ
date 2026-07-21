enum GameplayCommandType {
  moveLeft,
  moveRight,
  steer,
  accelerate,
  brake,
  nitro,
  pause,
  resume,
}

enum CommandState { start, stop }

class GameplayCommand {
  final GameplayCommandType type;
  final CommandState state;

  /// Analog payload. Only [GameplayCommandType.steer] uses it, carrying the
  /// normalized steering axis in [-1, 1].
  final double value;

  const GameplayCommand(
    this.type, {
    this.state = CommandState.start,
    this.value = 0.0,
  });

  @override
  String toString() =>
      'GameplayCommand(${type.name}, ${state.name}, value: $value)';
}

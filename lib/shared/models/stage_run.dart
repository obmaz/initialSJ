enum RunStatus { ready, running, cleared, failed }

class StageRun {
  final int livesRemaining;
  final String runId;
  final int stageNumber;
  final RunStatus status;
  final int score;
  final double mapProgress;
  final int currentLap;
  final int totalLaps;
  final int lapRemainingMeters;
  final int flagsCollected;
  final int totalFlags;
  final double currentSpeed;
  final double fuelRemaining;
  final double elapsedTime;

  /// Seconds left on the pre-race countdown. Zero once the race is live.
  final double countdownRemaining;
  final bool nitroReady;
  final int collisionCount;
  final int chasersNearby;

  StageRun({
    required this.runId,
    required this.stageNumber,
    this.livesRemaining = 3,
    this.status = RunStatus.ready,
    this.score = 0,
    this.mapProgress = 0.0,
    this.currentLap = 1,
    this.totalLaps = 2,
    this.lapRemainingMeters = 0,
    this.flagsCollected = 0,
    this.totalFlags = 0,
    this.currentSpeed = 0.0,
    this.fuelRemaining = 1.0,
    this.elapsedTime = 0.0,
    this.countdownRemaining = 0.0,
    this.nitroReady = true,
    this.collisionCount = 0,
    this.chasersNearby = 0,
  });

  StageRun copyWith({
    int? livesRemaining,
    RunStatus? status,
    int? score,
    double? mapProgress,
    int? currentLap,
    int? totalLaps,
    int? lapRemainingMeters,
    int? flagsCollected,
    int? totalFlags,
    double? currentSpeed,
    double? fuelRemaining,
    double? elapsedTime,
    double? countdownRemaining,
    bool? nitroReady,
    int? collisionCount,
    int? chasersNearby,
  }) {
    return StageRun(
      runId: runId,
      stageNumber: stageNumber,
      livesRemaining: livesRemaining ?? this.livesRemaining,
      status: status ?? this.status,
      score: score ?? this.score,
      mapProgress: mapProgress ?? this.mapProgress,
      currentLap: currentLap ?? this.currentLap,
      totalLaps: totalLaps ?? this.totalLaps,
      lapRemainingMeters: lapRemainingMeters ?? this.lapRemainingMeters,
      flagsCollected: flagsCollected ?? this.flagsCollected,
      totalFlags: totalFlags ?? this.totalFlags,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      fuelRemaining: fuelRemaining ?? this.fuelRemaining,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      countdownRemaining: countdownRemaining ?? this.countdownRemaining,
      nitroReady: nitroReady ?? this.nitroReady,
      collisionCount: collisionCount ?? this.collisionCount,
      chasersNearby: chasersNearby ?? this.chasersNearby,
    );
  }
}

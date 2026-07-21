enum RunOutcome { cleared, failed }

class ResultSummary {
  final int finalScore;
  final int stageNumber;
  final RunOutcome outcome;
  final int flagsCollected;
  final int coinsAwarded;
  final bool newBestScore;
  final double clearTimeSeconds;
  final int lapsCompleted;

  ResultSummary({
    required this.finalScore,
    required this.stageNumber,
    required this.outcome,
    required this.flagsCollected,
    required this.coinsAwarded,
    this.newBestScore = false,
    this.clearTimeSeconds = 0.0,
    this.lapsCompleted = 0,
  });

  factory ResultSummary.fromJson(Map<String, dynamic> json) {
    return ResultSummary(
      finalScore: json['finalScore'],
      stageNumber: json['stageNumber'],
      outcome: RunOutcome.values.firstWhere(
        (e) => e.name == json['outcome'],
        orElse: () => RunOutcome.failed,
      ),
      flagsCollected: json['flagsCollected'] ?? 0,
      coinsAwarded: json['coinsAwarded'] ?? 0,
      newBestScore: json['newBestScore'] ?? false,
      clearTimeSeconds: (json['clearTimeSeconds'] ?? 0.0).toDouble(),
      lapsCompleted: json['lapsCompleted'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'finalScore': finalScore,
      'stageNumber': stageNumber,
      'outcome': outcome.name,
      'flagsCollected': flagsCollected,
      'coinsAwarded': coinsAwarded,
      'newBestScore': newBestScore,
      'clearTimeSeconds': clearTimeSeconds,
      'lapsCompleted': lapsCompleted,
    };
  }
}

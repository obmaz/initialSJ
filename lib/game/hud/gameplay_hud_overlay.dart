import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:initialsj/game/engine/racing_game.dart';
import 'package:initialsj/game/engine/game_session_controller.dart';
import 'package:initialsj/shared/models/stage_run.dart';

class GameplayHudOverlay extends StatelessWidget {
  final GameSessionController sessionController;
  final FlameGame game;

  const GameplayHudOverlay({
    super.key,
    required this.sessionController,
    required this.game,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StageRun>(
      stream: sessionController.stateStream,
      builder: (context, snapshot) {
        final run = snapshot.data;
        if (run == null) return const SizedBox.shrink();
        final countdownValue = run.countdownRemaining.ceil();
        final showCountdown = run.countdownRemaining > 0;
        final speedValue = run.currentSpeed.round();
        final fuelPercent = (run.fuelRemaining * 100).round();
        final fuelColor = run.fuelRemaining > 0.5
            ? Colors.green
            : run.fuelRemaining > 0.25
            ? Colors.orange
            : const Color(0xFFFF5A5A);
        final racingGame = game is RacingGame ? game as RacingGame : null;

        return Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TopHudPanel(
                      run: run,
                      fuelPercent: fuelPercent,
                      speedValue: speedValue,
                      fuelColor: fuelColor,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PauseButton(onPressed: sessionController.pause),
                        const Spacer(),
                        if (racingGame != null) _MiniMapPanel(game: racingGame),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (showCountdown)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'READY',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$countdownValue',
                      style: const TextStyle(
                        color: Color(0xFFFFE66D),
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TopHudPanel extends StatelessWidget {
  const _TopHudPanel({
    required this.run,
    required this.fuelPercent,
    required this.speedValue,
    required this.fuelColor,
  });

  final StageRun run;
  final int fuelPercent;
  final int speedValue;
  final Color fuelColor;

  static const _panelAspectRatio = 1983 / 793;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final panelHeight = panelWidth / _panelAspectRatio;

        return SizedBox(
          width: panelWidth,
          height: panelHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/ui/bg_gameplay_hud_top.webp',
                  fit: BoxFit.fill,
                ),
              ),
              Positioned(
                left: panelWidth * 0.15,
                top: panelHeight * 0.32,
                width: panelWidth * 0.165,
                height: panelHeight * 0.36,
                child: _FuelModule(
                  fuelPercent: fuelPercent,
                  fuelColor: fuelColor,
                ),
              ),
              Positioned(
                left: panelWidth * 0.15,
                top: panelHeight * 0.01,
                child: _LivesStat(livesRemaining: run.livesRemaining),
              ),
              Positioned(
                left: panelWidth * 0.31,
                top: panelHeight * 0.23,
                width: panelWidth * 0.38,
                height: panelHeight * 0.42,
                child: _SpeedModule(
                  speedValue: speedValue,
                  lapRemainingMeters: run.lapRemainingMeters,
                ),
              ),
              Positioned(
                right: panelWidth * 0.13,
                top: panelHeight * 0.39,
                width: panelWidth * 0.19,
                height: panelHeight * 0.38,
                child: _StatusModule(run: run),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Entry point into [PauseOverlay]. Without it nothing in the app ever emitted
/// a pause command, leaving the whole pause flow unreachable.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pause',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xCC061013),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: const Icon(Icons.pause, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _MiniMapPanel extends StatelessWidget {
  const _MiniMapPanel({required this.game});

  final RacingGame game;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(painter: _MiniMapPainter(game: game)),
      ),
    );
  }
}

class _FuelModule extends StatelessWidget {
  const _FuelModule({required this.fuelPercent, required this.fuelColor});

  final int fuelPercent;
  final Color fuelColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HudLabel('FUEL'),
        const SizedBox(height: 1),
        Text(
          '$fuelPercent%',
          style: TextStyle(
            color: fuelColor,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}

class _SpeedModule extends StatelessWidget {
  const _SpeedModule({
    required this.speedValue,
    required this.lapRemainingMeters,
  });

  final int speedValue;
  final int lapRemainingMeters;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$lapRemainingMeters m',
            style: const TextStyle(
              color: Color(0xFFFFE36D),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFB6F2FF), Color(0xFF4AD7FF)],
            ).createShader(bounds),
            child: Text(
              speedValue.toString().padLeft(3, '0'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                height: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusModule extends StatelessWidget {
  const _StatusModule({required this.run});

  final StageRun run;

  String _formatTime(double seconds) {
    final totalSeconds = seconds.floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    final milliseconds = ((seconds - totalSeconds) * 1000).floor().clamp(
      0,
      999,
    );
    return '$minutes:$secs.${milliseconds.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -5),
          child: _HudMicroStat(
            label: '',
            value: _formatTime(run.elapsedTime),
            valueColor: const Color(0xFFFFD978),
            labelSize: 9,
            valueSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Transform.translate(
          offset: const Offset(0, 0),
          child: _HudMicroStat(
            label: 'LAP',
            value: '${run.currentLap}/${run.totalLaps}',
            labelSize: 9,
            valueSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        if (run.chasersNearby > 0)
          _HudMicroStat(
            label: 'CHASE',
            value: '${run.chasersNearby}',
            valueColor: const Color(0xFFFF7043),
            labelSize: 9,
            valueSize: 11,
          ),
      ],
    );
  }
}

class _HudLabel extends StatelessWidget {
  const _HudLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF91E8FF),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.4,
      ),
    );
  }
}

class _HudMicroStat extends StatelessWidget {
  const _HudMicroStat({
    required this.label,
    required this.value,
    this.valueColor = Colors.white,
    this.labelSize = 10,
    this.valueSize = 13,
  });

  final String label;
  final String value;
  final Color valueColor;
  final double labelSize;
  final double valueSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              color: Colors.white60,
              fontSize: labelSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: valueColor,
              fontSize: valueSize,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivesStat extends StatelessWidget {
  const _LivesStat({required this.livesRemaining});

  final int livesRemaining;

  @override
  Widget build(BuildContext context) {
    final hearts = List.generate(
      livesRemaining.clamp(0, 5),
      (_) => const Padding(
        padding: EdgeInsets.only(right: 4),
        child: Icon(Icons.favorite, size: 17, color: Color(0xFFD32F2F)),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: hearts.isEmpty
          ? const [
              Text(
                '-',
                style: TextStyle(
                  color: Color(0xFFD32F2F),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ]
          : hearts,
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  const _MiniMapPainter({required this.game});

  final RacingGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final stageSize = game.stageWorldSize;
    if (stageSize.width <= 0 || stageSize.height <= 0) {
      return;
    }

    final miniMapRect = Offset.zero & size;
    final backgroundPaint = Paint()..color = const Color(0xCC061013);
    final gridPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final roadPaint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    final playerPaint = Paint()..color = const Color(0xFF7CFF8A);
    final flagPaint = Paint()..color = const Color(0xFFFFE36D);
    final policePaint = Paint()..color = const Color(0xFFFF5A5A);

    canvas.drawRRect(
      RRect.fromRectAndRadius(miniMapRect, const Radius.circular(14)),
      backgroundPaint,
    );

    final rows = game.miniMapRows;
    final playerX = game.playerWorldPosition.x.clamp(0.0, stageSize.width);
    final playerY = game.playerWorldPosition.y.clamp(0.0, stageSize.height);
    const horizontalPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 10.0;
    final contentWidth = size.width - (horizontalPadding * 2);
    final contentHeight = size.height - topPadding - bottomPadding;
    final scale = contentWidth / stageSize.width;
    final visibleWorldHeight = contentHeight / scale;
    final playerMiniMapY = size.height - bottomPadding - 6;
    final viewportTopWorldY = (playerY - visibleWorldHeight).clamp(
      0.0,
      stageSize.height - visibleWorldHeight,
    );
    final viewportRect = Rect.fromLTWH(
      horizontalPadding,
      topPadding,
      contentWidth,
      contentHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(viewportRect, const Radius.circular(10)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.03)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (rows.isNotEmpty) {
      final cellWidth = contentWidth / rows.first.length;
      final cellHeight = cellWidth;
      for (var row = 0; row < rows.length; row++) {
        final line = rows[row];
        final rowWorldY = row * (stageSize.height / rows.length);
        final rowScreenY =
            topPadding + ((rowWorldY - viewportTopWorldY) * scale);
        if (rowScreenY + cellHeight < topPadding ||
            rowScreenY > size.height - bottomPadding) {
          continue;
        }
        for (var col = 0; col < line.length; col++) {
          final tile = line[col];
          if (tile == '1' || tile == '2') {
            continue;
          }
          canvas.drawRect(
            Rect.fromLTWH(
              horizontalPadding + (col * cellWidth),
              rowScreenY,
              cellWidth,
              cellHeight,
            ),
            roadPaint,
          );
        }
      }
    }

    Offset project(double worldX, double worldY) {
      final dx =
          horizontalPadding +
          (worldX / stageSize.width).clamp(0.0, 1.0) * contentWidth;
      final dy = topPadding + ((worldY - viewportTopWorldY) * scale);
      return Offset(dx, dy);
    }

    for (final flag in game.remainingFlagPositions) {
      final point = project(flag.x, flag.y);
      if (point.dy < topPadding || point.dy > size.height - bottomPadding) {
        continue;
      }
      final path = Path()
        ..moveTo(point.dx, point.dy - 4)
        ..lineTo(point.dx + 3.5, point.dy + 3)
        ..lineTo(point.dx - 3.5, point.dy + 3)
        ..close();
      canvas.drawPath(path, flagPaint);
    }

    for (final chaser in game.chaserWorldPositions) {
      final point = project(chaser.x, chaser.y);
      if (point.dy < topPadding || point.dy > size.height - bottomPadding) {
        continue;
      }
      canvas.drawCircle(point, 3.2, policePaint);
    }

    final playerPoint = Offset(
      horizontalPadding +
          (playerX / stageSize.width).clamp(0.0, 1.0) * contentWidth,
      playerMiniMapY,
    );
    canvas.drawCircle(playerPoint, 4.2, playerPaint);

    canvas.drawLine(
      Offset(playerPoint.dx, topPadding),
      Offset(playerPoint.dx, size.height - bottomPadding),
      gridPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) => true;
}

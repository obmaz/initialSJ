import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:initialsj/app/router/app_router.dart';
import 'package:initialsj/game/world/stage_layout.dart';
import 'package:initialsj/shared/models/result_summary.dart';
import 'package:initialsj/shared/state/app_state_controller.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  String _formatTime(double seconds) {
    final totalSeconds = seconds.floor();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateController>();
    final summary =
        appState.latestResult ??
        ResultSummary(
          finalScore: 0,
          stageNumber: appState.activeRun?.stageNumber ?? 1,
          outcome: RunOutcome.failed,
          flagsCollected: 0,
          coinsAwarded: 0,
        );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        appState.endRun();
        context.go(AppRouter.titlePath);
      },
      child: Scaffold(
        body: summary.outcome == RunOutcome.cleared
            ? _buildClearResult(context, appState, summary)
            : _buildGameOverResult(context, appState, summary),
      ),
    );
  }

  Widget _buildClearResult(
    BuildContext context,
    AppStateController appState,
    ResultSummary summary,
  ) {
    final hasNextStage = summary.stageNumber < StageLayout.maxStageNumber;
    final nextStage = summary.stageNumber + 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/backgrounds/bg_result_stage_clear.webp',
              fit: BoxFit.fill,
            ),
            Positioned(
              left: 0,
              right: 0,
              top: constraints.maxHeight * 0.16,
              child: Column(
                children: [
                  Text(
                    _formatTime(summary.clearTimeSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'LAP ${summary.lapsCompleted}/2',
                    style: const TextStyle(
                      color: Color(0xFFFFE36D),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _tapArea(
              constraints: constraints,
              left: 0.16,
              top: 0.81,
              width: 0.69,
              height: 0.14,
              onTap: () {
                if (hasNextStage) {
                  appState.startNewRun(nextStage);
                  context.pushReplacement(AppRouter.gameplayPath);
                  return;
                }
                appState.endRun();
                context.go(AppRouter.titlePath);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildGameOverResult(
    BuildContext context,
    AppStateController appState,
    ResultSummary summary,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/backgrounds/bg_result_game_over.webp',
              fit: BoxFit.fill,
            ),
            _tapArea(
              constraints: constraints,
              left: 0.30,
              top: 0.42,
              width: 0.40,
              height: 0.08,
              onTap: () {
                appState.startNewRun(summary.stageNumber);
                context.pushReplacement(AppRouter.gameplayPath);
              },
            ),
            _tapArea(
              constraints: constraints,
              left: 0.16,
              top: 0.865,
              width: 0.68,
              height: 0.11,
              onTap: () {
                appState.endRun();
                context.go(AppRouter.titlePath);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _tapArea({
    required BoxConstraints constraints,
    required double left,
    required double top,
    required double width,
    required double height,
    required VoidCallback onTap,
  }) {
    return Positioned(
      left: left * constraints.maxWidth,
      top: top * constraints.maxHeight,
      width: width * constraints.maxWidth,
      height: height * constraints.maxHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const ColoredBox(color: Colors.transparent),
      ),
    );
  }
}

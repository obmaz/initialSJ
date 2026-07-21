import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:initialsj/game/engine/game_session_controller.dart';
import 'package:initialsj/game/engine/gameplay_commands.dart';
import 'package:initialsj/game/hud/gameplay_hud_overlay.dart';
import 'package:initialsj/shared/models/stage_run.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameSessionController sessionController;

  setUp(() {
    sessionController = GameSessionController();
  });

  tearDown(() {
    sessionController.dispose();
  });

  StageRun runWith({
    double fuelRemaining = 1.0,
    double currentSpeed = 0,
    double countdownRemaining = 0,
    int livesRemaining = 3,
    int currentLap = 1,
    int chasersNearby = 0,
  }) {
    return StageRun(
      runId: 'test-run',
      stageNumber: 1,
      fuelRemaining: fuelRemaining,
      currentSpeed: currentSpeed,
      countdownRemaining: countdownRemaining,
      livesRemaining: livesRemaining,
      currentLap: currentLap,
      chasersNearby: chasersNearby,
      status: RunStatus.running,
    );
  }

  /// Mounts the overlay once. A bare [FlameGame] exercises the branch where the
  /// game is not a RacingGame, which skips the minimap rather than crashing.
  Future<void> mountHud(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GameplayHudOverlay(
          sessionController: sessionController,
          game: FlameGame(),
        ),
      ),
    );
  }

  /// Pushes a new run state through the session stream, like the engine does.
  Future<void> pushState(WidgetTester tester, StageRun run) async {
    sessionController.updateState(run);
    // One frame to let the broadcast stream event land, a second to render the
    // rebuild it triggers.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders nothing until the first state arrives', (tester) async {
    await mountHud(tester);

    expect(find.textContaining('%'), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('displays fuel, speed and lap', (tester) async {
    await mountHud(tester);
    await pushState(
      tester,
      runWith(fuelRemaining: 0.8, currentSpeed: 42, currentLap: 2),
    );

    expect(find.text('FUEL'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    // Speed is zero padded to three digits.
    expect(find.text('042'), findsOneWidget);
    // Lap is drawn as a RichText label/value pair.
    expect(find.text('LAP 2/2', findRichText: true), findsOneWidget);
  });

  testWidgets('fuel colour warns as the tank empties', (tester) async {
    Color fuelColour() =>
        tester.widget<Text>(find.textContaining('%')).style!.color!;

    await mountHud(tester);

    await pushState(tester, runWith(fuelRemaining: 0.9));
    expect(fuelColour(), Colors.green);

    await pushState(tester, runWith(fuelRemaining: 0.3));
    expect(fuelColour(), Colors.orange);

    await pushState(tester, runWith(fuelRemaining: 0.1));
    expect(fuelColour(), const Color(0xFFFF5A5A));
  });

  testWidgets('shows the countdown only while it is running', (tester) async {
    await mountHud(tester);

    await pushState(tester, runWith(countdownRemaining: 2.4));
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await pushState(tester, runWith(countdownRemaining: 0.4));
    expect(find.text('1'), findsOneWidget);

    await pushState(tester, runWith(countdownRemaining: 0));
    expect(find.text('READY'), findsNothing);
  });

  testWidgets('shows one heart per remaining life', (tester) async {
    await mountHud(tester);

    await pushState(tester, runWith(livesRemaining: 3));
    expect(find.byIcon(Icons.favorite), findsNWidgets(3));

    await pushState(tester, runWith(livesRemaining: 1));
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await pushState(tester, runWith(livesRemaining: 0));
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.text('-'), findsOneWidget);
  });

  testWidgets('only shows the chase counter when chasers are near', (
    tester,
  ) async {
    await mountHud(tester);

    await pushState(tester, runWith(chasersNearby: 0));
    expect(find.text('CHASE 2', findRichText: true), findsNothing);

    await pushState(tester, runWith(chasersNearby: 2));
    expect(find.text('CHASE 2', findRichText: true), findsOneWidget);
  });

  testWidgets('the pause button emits a pause command', (tester) async {
    final commands = <GameplayCommand>[];
    sessionController.commandStream.listen(commands.add);

    await mountHud(tester);
    await pushState(tester, runWith());

    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(commands.map((command) => command.type), <GameplayCommandType>[
      GameplayCommandType.pause,
    ]);
  });
}

# 코드 리뷰 — initialsj

- **대상**: `main` 브랜치 (`f0588d7`)
- **범위**: `lib/` 전체 (24개 파일, 약 4,350줄), `test/`, `.github/workflows/`
- **제외**: 보안 (요청에 따라 검토하지 않음)
- **검증**: `flutter analyze` 무결점 / `flutter test` 12건 통과 / `dart format` 3개 파일 미적용

> **상태: 21건 전부 조치 완료.** 조치 내역과 재검증 결과는 문서 끝의 [조치 결과](#조치-결과)를 참고하십시오.
> 아래 본문은 조치 이전 시점의 리뷰 원문입니다.

---

## 요약

구조는 깔끔합니다. `app / core / features / game / shared` 계층 분리가 일관적이고, 게임 엔진과 UI가 `GameSessionController`의 스트림으로 분리되어 있어 결합도가 낮습니다. 정적 분석도 깨끗합니다.

문제는 세 군데에 몰려 있습니다.

1. **런타임 크래시 가능성 1건** — 게임 로드 전 조이스틱 조작 시 `LateInitializationError`
2. **렌더링/충돌 판정 핫패스의 심각한 비효율** — 모바일 프레임률에 직접 영향
3. **테스트가 사실상 없음** — 6개 파일 중 3개가 빈 껍데기, 1개는 자기 자신을 검증하는 무의미한 단언

또한 도달 불가능한 기능(일시정지, 브레이크, 스킬 버튼)과 죽은 코드가 누적되어 있습니다.

| 심각도 | 건수 |
|---|---|
| 🔴 High | 4 |
| 🟠 Medium | 8 |
| 🟡 Low | 9 |

---

## 🔴 High

### H-1. 게임 로드 완료 전 조이스틱 조작 시 크래시

[gameplay_screen.dart:241](lib/features/gameplay/gameplay_screen.dart#L241)

```dart
void _updateJoystickSteering(double steering) {
  if ((_joystickSteering - steering).abs() < 0.001) return;
  _joystickSteering = steering;
  _game.player.setSteeringInput(steering);   // ← late final, onLoad에서 초기화
}
```

`CameraCenteredGame.player`는 `late final`이며 [camera_centered_game.dart:70](lib/game/engine/camera_centered_game.dart#L70)의 비동기 `onLoad()`에서 대입됩니다. 반면 조작 UI는 `GameWidget` 바깥의 `Positioned`로 배치되어 **게임 로드 여부와 무관하게 즉시 렌더링·터치 수용**합니다.

스프라이트 3종 + 스테이지 텍스트 로딩이 끝나기 전(웹 초회 로딩·저사양 단말에서 수백 ms) 조이스틱을 드래그하면 `LateInitializationError`로 앱이 죽습니다.

**수정 방향**: 화면 곳곳에서 이미 쓰는 `_game.isLoaded` 가드를 추가하거나, 더 나은 방법으로 조향 입력도 나머지 입력과 동일하게 `sessionController` 커맨드 스트림으로 보내십시오. 현재 조향만 컨트롤러를 우회해 엔진 내부를 직접 만지고 있어서 이 문제가 생겼습니다 (M-1 참조).

---

### H-2. 도로 렌더링 루프의 프레임당 블러 40회 + Paint 재할당

[camera_centered_stage.dart:176-187](lib/game/world/camera_centered_stage.dart#L176-L187)

```dart
for (var index = segmentCount; index >= 1; index--) {   // 40회
  ...
  final roadShadowPaint = Paint()
    ..color = const Color(0xAA0C0D18)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);   // ← 세그먼트마다 블러
  canvas.drawPath(..., roadShadowPaint);
```

`MaskFilter.blur`는 GPU에서 오프스크린 패스를 유발하는 가장 비싼 연산 중 하나입니다. 이걸 **매 프레임 40번** 실행합니다. 같은 루프에서 `LinearGradient(...).createShader()`도 세그먼트마다 새로 만듭니다 ([165-173행](lib/game/world/camera_centered_stage.dart#L165-L173)).

모바일 세로 화면 기준 프로젝트인데 이 한 루프가 프레임 예산을 대부분 소진할 가능성이 높습니다.

**수정 방향**:
- 그림자는 루프 밖에서 도로 전체 폴리곤 하나로 한 번만 그리거나 제거
- `Paint`/`Shader`는 필드로 캐시. 그라디언트는 짝/홀 2종뿐이므로 `Rect`가 바뀔 때만 재생성
- `shoulderPaint`, `borderPaint`는 이미 루프 밖에 있으나 루프 안에서 `..strokeWidth =`로 **공유 객체를 변형**하고 있습니다 ([196-206행](lib/game/world/camera_centered_stage.dart#L196-L206)). 동작은 하지만 위험한 패턴입니다

---

### H-3. 도로 형상 샘플링이 프레임당 수천 회 반복 (캐시 없음)

[camera_centered_stage.dart:509](lib/game/world/camera_centered_stage.dart#L509) `_roadSampleForWorldY`

이 함수는 호출마다 5개 행을 조회하고 가중 평균을 냅니다. 호출 경로를 따라가 보면:

- `_renderRoad` 세그먼트 40개 × 좌/우 근·원점 4개 = 160개 점
- 점마다 `projectWorldPosition` → `roadCenterRatioForWorldY` + `roadWidthRatioForWorldY` + `roadCenterXForWorldY`(내부 2회) + `roadHalfWidthForWorldY`(1회)
- 여기에 각 점 좌표를 구하려고 `roadLeftForWorldY` / `roadRightForWorldY`가 추가로 호출됨

대략 **프레임당 2,000회 이상**, 내부 조회까지 합치면 **1만 회 이상의 Map 조회**가 도로 하나를 그리는 데 쓰입니다.

더 나쁜 것은 폴백 경로입니다:

```dart
StageRoadSpan? _roadSpanForRow(int row) {
  final exact = _roadSpansByRow[wrappedRow];
  if (exact != null) return exact;
  for (var offset = 1; offset < _layout.rows; offset++) {   // ← 최악 O(rows)
```

캐시 미스가 나면 행 수(238~311)만큼 선형 탐색합니다. 이게 5중 루프 안에 있습니다.

**수정 방향**: `_roadSpansByRow`는 청크 로딩 시점에 확정되므로, 그때 **행별 보간 결과를 배열로 미리 계산**해 두고 렌더링에서는 인덱싱만 하십시오. `worldY → row` 변환도 상수 시간입니다. 프레임 단위 메모이제이션만 넣어도 큰 개선이 됩니다.

---

### H-4. 벽 충돌 판정이 전체 선형 탐색 — 프레임당 3만 회 이상

[camera_centered_stage.dart:405](lib/game/world/camera_centered_stage.dart#L405)

```dart
bool collidesWithWall(Rect rect) {
  for (final wall in _walls) {   // 공간 분할 없음
```

`stage1.txt`는 30열 × 238행이고 도로 바깥은 대부분 `2`(나무)입니다. [stage_layout.dart:232](lib/game/world/stage_layout.dart#L232)에서 도로 스팬 밖의 벽만 담는다 해도 행당 20개 이상 → **약 5,000개 이상의 벽**이 리스트에 쌓입니다.

이 리스트를 다음이 매 프레임 스캔합니다:
- 플레이어 `_moveAlongAxis` × 2축 ([camera_centered_player.dart:252](lib/game/entities/camera_centered_player.dart#L252))
- 추격 차량 N대 × 2축 ([camera_centered_chaser.dart:85](lib/game/entities/camera_centered_chaser.dart#L85))

추격차 2대 기준 프레임당 **3만 번 이상의 사각형 비교**입니다.

부수적으로 루프 내부에 수동 AABB 조기 탈출과 `rect.overlaps`가 중복 구현되어 있습니다 — `overlaps` 자체가 같은 검사를 합니다.

**수정 방향**: `_walls`를 행 단위 버킷(`Map<int, List<_StageWall>>`)으로 색인하고, 히트박스가 걸치는 행 2~3개만 조회하십시오. 벽은 셀 격자에 정렬되어 있어 구현이 간단합니다.

---

## 🟠 Medium

### M-1. 조향 입력만 커맨드 스트림 아키텍처를 우회

`GameSessionController`는 모든 입력을 스트림으로 흘리도록 설계되었고 실제로 가속/좌우/브레이크/니트로가 그렇게 동작합니다. 그런데 아날로그 조향만 [gameplay_screen.dart:241](lib/features/gameplay/gameplay_screen.dart#L241)에서 `_game.player`를 직접 호출합니다.

그 결과 조향 경로가 **이중화**됩니다 — 이산 입력(`moveLeft`/`moveRight` → `movingLeft`/`movingRight`)과 아날로그 입력(`_steeringInput`)이 각각 별도로 속도에 기여하고, 이 둘을 다시 화해시키느라 [camera_centered_player.dart:203-218](lib/game/entities/camera_centered_player.dart#L203-L218)의 속도 클램프 로직이 읽기 어려운 상태가 되었습니다:

```dart
if (currentSpeed > maxSpeed && previousSpeed <= maxSpeed) { ... }
if (currentSpeed > previousSpeed && previousSpeed > maxSpeed) { ... }
```

`GameplayCommand`에 `double value` 필드를 추가해 조향을 스트림으로 통합하고, 플레이어 쪽 조향 경로를 하나로 합치면 H-1도 함께 해결됩니다.

---

### M-2. 배경 패럴랙스가 60fps로 위젯 트리 전체를 재빌드

[gameplay_screen.dart:273-289](lib/features/gameplay/gameplay_screen.dart#L273-L289)

```dart
_parallaxTicker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
...
return AnimatedBuilder(
  animation: Listenable.merge([_parallaxTicker, widget.runListenable]),
  builder: (context, child) {          // ← child 미사용
    ...
    return LayoutBuilder(builder: ... Image.asset(backgroundAsset) ...);
```

문제 세 가지:
- `AnimatedBuilder`의 `child` 파라미터를 쓰지 않아 최적화 여지를 전부 버림
- 매 프레임 `LayoutBuilder` + `Image.asset` 위젯 재생성 (이미지 자체는 캐시되지만 위젯/엘리먼트 작업은 발생)
- 애니메이션 값(`_parallaxTicker.value`)을 실제로 **읽지 않습니다**. 오직 프레임 틱을 강제하는 용도로만 쓰입니다

패럴랙스 값은 전부 `widget.game`에서 직접 읽으므로, 이 배경 전체를 Flame 컴포넌트로 옮기거나 `CustomPaint` + `repaint: Listenable`로 바꾸면 위젯 재빌드 없이 같은 결과를 냅니다.

---

### M-3. 일시정지 기능 도달 불가 — UI 전체가 죽은 코드

`GameSessionController.pause()`가 **어디에서도 호출되지 않습니다**:

```
lib/game/engine/game_session_controller.dart:45  ← 정의만 존재
```

따라서 `_isPaused`는 영원히 `false`이고, [pause_overlay.dart](lib/features/gameplay/widgets/pause_overlay.dart) 68줄 전체와 [gameplay_screen.dart:55-63](lib/features/gameplay/gameplay_screen.dart#L55-L63)의 처리 로직, `PauseOverlay` 안의 RESUME/RESTART/HOME 버튼이 전부 도달 불가능합니다.

HUD에 일시정지 버튼을 추가하거나, 기능을 접었다면 관련 코드를 삭제하십시오.

---

### M-4. 브레이크와 스킬 버튼도 배선되지 않음

- **브레이크**: `movingDown`은 정지 커맨드(`_releaseGameplayInputs`)로만 도달합니다. 즉 감속 수단이 관성 항력뿐입니다
- **스킬 버튼**: [gameplay_screen.dart:196](lib/features/gameplay/gameplay_screen.dart#L196) — `onPressed: () {}`, `onReleased: () {}`. 화면 하단 92×92 공간을 차지하면서 아무 동작도 하지 않습니다

플레이어가 누를 수 있는 버튼이 반응하지 않는 것은 명백한 UX 결함입니다.

---

### M-5. 카운트다운이 표시만 되고 실제로 멈추지 않음

[gameplay_hud_overlay.dart:26-27](lib/game/hud/gameplay_hud_overlay.dart#L26-L27)에서 `READY / 3 / 2 / 1`을 띄우지만, [camera_centered_game.dart:97](lib/game/engine/camera_centered_game.dart#L97) `update()`에는 이를 반영하는 게이트가 없습니다.

카운트다운 중에도 추격 차량이 접근하고, 연료가 소모되고, 경과 시간이 흐르고, 조작이 그대로 먹힙니다. 화면은 "준비"라고 말하는데 게임은 이미 시작된 상태입니다.

---

### M-6. 니트로에 연료 비용이 없음 (선언된 상수가 미사용)

```dart
static const double nitroFuelDrainMultiplier = 2.4;   // 선언만, 참조 0회
```

[camera_centered_game.dart:29](lib/game/engine/camera_centered_game.dart#L29). `_updateFuel`는 이 값을 쓰지 않습니다. 니트로는 **무제한·무비용·쿨다운 없음**이라 연타로 최고 속도를 계속 갱신할 수 있습니다:

```dart
void applyNitroBurst() {
  final boostedSpeed = currentSpeed + nitroBoostPerInterval;   // maxSpeed 상한 없음
```

[camera_centered_player.dart:154](lib/game/entities/camera_centered_player.dart#L154). 게임 밸런스가 무너지는 지점입니다. 의도한 설계라면 상수를 지우고, 아니라면 배선하십시오.

---

### M-7. 결과 요약이 최대 100ms 낡은 상태를 참조

[camera_centered_game.dart:115-120](lib/game/engine/camera_centered_game.dart#L115-L120)

```dart
if (_stateAccumulator >= stateUpdateInterval) {   // 0.1초마다
  _emitStateUpdate();
  _stateAccumulator = 0.0;
}
_reportOutcomeIfNeeded();   // ← 즉시 발화
```

상태 갱신은 10Hz로 스로틀되지만 결과 보고는 즉시 나갑니다. 수신 측 [gameplay_screen.dart:78](lib/features/gameplay/gameplay_screen.dart#L78)은 `appState.activeRun`에서 점수·경과시간·랩을 읽으므로 **최대 100ms 낡은 스냅샷**으로 최종 결과가 확정됩니다. 마지막 순간에 먹은 깃발이 점수에서 누락될 수 있습니다.

`reportOutcome` 직전에 `_emitStateUpdate()`를 강제 호출하거나, `RunOutcome` 대신 최종 `StageRun`을 함께 전달하십시오.

부수적으로, 같은 리스너에서 `run == null`이면 조용히 `return`합니다 — 이 경우 플레이어는 결과 화면으로 넘어가지 못하고 게임플레이 화면에 갇힙니다.

---

### M-8. 점수와 코인 산식이 서로 모순

| 항목 | 산식 | 위치 |
|---|---|---|
| 점수 | `flags × 100 − collisions × 200` | [camera_centered_game.dart:185](lib/game/engine/camera_centered_game.dart#L185) |
| 코인 | `flags × 100` | [gameplay_screen.dart:88](lib/features/gameplay/gameplay_screen.dart#L88) |

충돌 패널티가 점수에만 적용되고 보상에는 적용되지 않습니다. 또 점수는 음수가 될 수 있는데 하한 클램프가 없고, 실패한 런에도 코인이 전액 지급됩니다.

같은 함수의 `distanceReached: run.flagsCollected.toDouble()`은 **필드 이름과 담긴 값이 다릅니다** — "도달 거리"에 깃발 개수가 들어갑니다. 다행히 현재 어느 화면에서도 표시하지 않지만, 나중에 쓰는 사람이 반드시 오해합니다.

---

## 🟡 Low

### L-1. 청크 스트리밍 로직 전체가 죽은 코드

```dart
static const int initialLoadedRowCount = 500;
static const int additionalLoadedRowCount = 250;
```

현재 스테이지는 238행·311행입니다. `_loadedStartRow = (rows - 500).clamp(0, rows)`는 항상 **0**이 되고, `_maybeLoadMoreRows()`는 첫 줄에서 즉시 반환합니다 ([camera_centered_stage.dart:454](lib/game/world/camera_centered_stage.dart#L454)).

점진 로딩 코드([453-500행](lib/game/world/camera_centered_stage.dart#L453-L500))는 한 번도 실행되지 않았고, 따라서 **검증된 적이 없습니다**. 500행 넘는 스테이지를 추가하는 순간 처음으로 동작하는데 그때 버그가 드러날 겁니다.

### L-2. 미사용 public API

| 심볼 | 위치 |
|---|---|
| `viewportInWorld` | [camera_centered_game.dart:242](lib/game/engine/camera_centered_game.dart#L242) |
| `normalizedStageX` | [camera_centered_game.dart:255](lib/game/engine/camera_centered_game.dart#L255) |
| `worldRenderOffset` | [camera_centered_game.dart:277](lib/game/engine/camera_centered_game.dart#L277) |
| `collectedFlags` | [camera_centered_stage.dart:348](lib/game/world/camera_centered_stage.dart#L348) — 매 호출 전체 스캔 |
| `_renderBackdrop` | [camera_centered_stage.dart:54](lib/game/world/camera_centered_stage.dart#L54) — 주석만 있는 빈 함수 |
| `RunStatus.paused` / `.exited` | [stage_run.dart:1](lib/shared/models/stage_run.dart#L1) — 어디서도 대입 안 됨 |

### L-3. `depthCompressionPower = 1.0` — 무의미한 연산

```dart
final compressedT = math.pow(t, depthCompressionPower).toDouble().clamp(0.0, 1.0);
```

지수가 `1.0`이므로 `pow` 호출이 항등 함수입니다. 프레임당 수백 회 호출되는 경로([camera_centered_game.dart:307](lib/game/engine/camera_centered_game.dart#L307))에서 순수한 낭비입니다. 튜닝 여지를 남기려는 의도라면 주석으로 명시하십시오.

### L-4. 의미 없는 래퍼 위젯 3종

[gameplay_screen.dart](lib/features/gameplay/gameplay_screen.dart)의 `_NitroButton`(363행), `_SkillButton`(384행)은 상태가 없는데도 `StatefulWidget`이며, 하는 일은 `_ActionButton`에 에셋 경로를 넘기는 것뿐입니다. `_JoystickPanel`(460행)은 `_VirtualJoystick`을 그대로 통과시키는 순수 패스스루입니다.

`_ActionButton(assetPath: ...)`을 직접 쓰면 100줄 가까이 사라집니다.

### L-5. `Offset2`는 `dart:ui`의 `Offset` 중복

[stage_run.dart:81](lib/shared/models/stage_run.dart#L81). 모델 레이어의 Flutter 의존성을 피하려는 의도로 보이지만, 같은 `shared/models` 폴더의 [vehicle_spec.dart:1](lib/shared/models/vehicle_spec.dart#L1)이 이미 `dart:ui`를 임포트하고 있어 일관성이 없습니다. 게다가 `playerPosition` 필드는 어디서도 읽히지 않습니다.

### L-6. `CameraCentered` 접두사가 정보를 전달하지 않음

`CameraCenteredGame` / `CameraCenteredStage` / `CameraCenteredPlayer` / `CameraCenteredChaser` — 게임이 하나뿐이고 대안 구현이 없으므로 이 접두사는 매 참조마다 14자를 더할 뿐 아무것도 구분하지 않습니다. `RacingGame` / `Stage` / `Player` / `Chaser`로 충분합니다. (파일명도 동일)

### L-7. 프로필 로드 실패가 조용히 진행 상황을 전부 삭제

[local_storage_service.dart:20-24](lib/core/services/local_storage_service.dart#L20-L24)

```dart
try {
  return PlayerProfile.fromJson(jsonDecode(jsonString));
} catch (e) {
  return null;   // 로그도, 백업도 없음
}
```

`PlayerProfile.fromJson`의 `playerId: json['playerId']`는 암묵적 `dynamic → String` 캐스트라 저장 포맷이 바뀌면 던집니다. 그러면 코인·최고점수·보유 차량이 **말없이 초기값으로 리셋**되고, 사용자는 이유를 알 수 없습니다. 최소한 `debugPrint`로 흔적을 남기고, `version` 필드를 넣어 마이그레이션 경로를 확보하십시오.

관련해서 [app_state_controller.dart:113](lib/shared/state/app_state_controller.dart#L113)의 `owned.first`는 `startsUnlocked` 차량이 하나도 없으면 예외를 던집니다. 현재 카탈로그에는 2대가 있어 안전하지만, 카탈로그 편집 한 번으로 앱이 시작조차 못 하게 됩니다.

### L-8. 테스트가 실질적으로 존재하지 않음

`flutter test`는 12건 통과라고 보고하지만 내용을 보면:

| 파일 | 상태 |
|---|---|
| `test/game/gameplay_rules_test.dart` | **3건 전부 빈 본문** (주석만) |
| `test/widget/gameplay_hud_test.dart` | **2건 전부 빈 본문** |
| `test/widget/gameplay_layout_reference_test.dart` | **동어반복** — 아래 참조 |
| `test/unit/app_state_controller_test.dart` | 실질 검증 3건 |
| `test/unit/local_storage_service_test.dart` | 실질 검증 2건 |
| `test/widget/title_to_gameplay_flow_test.dart` | 실질 검증 1건 |

특히 레이아웃 테스트는 아무것도 검증하지 않습니다:

```dart
const hudHeightFactor = 0.12;
expect(hudHeightFactor, 0.12);   // 로컬 상수를 자기 자신과 비교
```

프로덕션 코드를 임포트조차 하지 않으며, `0.12`/`0.25`는 실제 코드의 어떤 값과도 대응하지 않습니다 (실제 컨트롤 높이 계수는 [gameplay_screen.dart:125](lib/features/gameplay/gameplay_screen.dart#L125)에서 `0.21`).

**빈 테스트가 통과로 집계되는 것이 무테스트보다 나쁩니다** — 커버리지가 있다는 착각을 만듭니다. 우선순위를 매긴다면:

1. `StageLayout.parse` — 순수 함수라 테스트가 쉽고, 도로 스팬/벽/깃발 파싱이 게임 전체의 기반
2. `AppStateController.buyVehicle` / `selectVehicle` — 잔액 부족, 중복 구매, 미보유 차량 선택 등 분기가 실제로 있음
3. `VehicleSpec._scaleLevel` 경계값 (레벨 1, 10, 범위 밖)

### L-9. CI가 분석·테스트·포맷을 검증하지 않음

[.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml)은 `pub get` → `build web` → 배포만 수행합니다. `flutter analyze`도 `flutter test`도 없습니다.

실제로 지금 `dart format`이 3개 파일에서 실패합니다:

```
Changed lib/features/results/result_screen.dart
Changed lib/game/engine/game_session_controller.dart
Changed lib/shared/widgets/retro_button.dart
```

`game_session_controller.dart`는 줄 끝 공백과 100자 초과 라인이 섞여 있어 나머지 코드베이스와 눈에 띄게 다릅니다.

빌드 잡 앞에 세 줄을 추가하면 회귀를 막을 수 있습니다:

```yaml
- run: dart format --output=none --set-exit-if-changed lib test
- run: flutter analyze --fatal-infos
- run: flutter test
```

---

## 권장 처리 순서

| 순서 | 항목 | 근거 |
|---|---|---|
| 1 | H-1 조이스틱 크래시 | 유일한 확정 크래시. 배포 중인 웹 빌드에 노출됨 |
| 2 | L-9 CI 게이트 | 한 번에 끝나고 이후 모든 회귀를 차단 |
| 3 | H-2 · H-3 · H-4 | 모바일 프레임률 직결. 셋 다 렌더/충돌 핫패스에 몰려 있어 한 번에 처리 가능 |
| 4 | M-3 · M-4 · M-5 | 사용자가 바로 체감하는 미배선 기능 |
| 5 | M-6 · M-8 | 게임 밸런스 정합성 |
| 6 | M-1 · M-2 | 아키텍처 정리. 3·4번을 먼저 하면 범위가 줄어듦 |
| 7 | L-8 테스트 | 위 변경들의 안전망이 되므로 리팩터링과 병행 |
| 8 | L-1~L-7 | 죽은 코드·네이밍 정리 |

---

# 조치 결과

권장 처리 순서대로 21건 전부 반영했습니다.

**재검증**: `flutter analyze` 무결점 · `dart format` 변경 없음 · `flutter test` **57건 통과**(이전 12건, 그중 5건은 빈 껍데기) · `flutter build web --release` 성공

## 1. 크래시

| 항목 | 조치 |
|---|---|
| H-1 | 조향 입력을 `GameSessionController.steer()` → 커맨드 스트림 경유로 전환. `GameplayCommand`에 아날로그 `value` 필드와 `steer` 타입 추가. UI가 `_game.player`를 직접 참조하지 않으므로 로드 전 입력이 무해해짐 |

## 2. CI 게이트

| 항목 | 조치 |
|---|---|
| L-9 | `deploy-pages.yml` 빌드 잡에 `dart format --set-exit-if-changed` → `flutter analyze --fatal-infos` → `flutter test`를 배포 전 단계로 추가. 미적용 상태였던 3개 파일 포맷 정리 |

## 3. 성능

| 항목 | 조치 |
|---|---|
| H-2 | 세그먼트별 `MaskFilter.blur` 40회 → 도로 전체 1회 단색 오버레이. 세그먼트별 `LinearGradient` 셰이더 생성 → 짝/홀 2개 캐시 `Paint`. 모든 `Paint`를 필드로 캐시해 렌더 루프 내 할당 제거. `shoulderInset = 0`으로 완전히 덮여 보이지 않던 갓길 채우기 삭제. 경계점을 세그먼트마다 두 번 투영하던 것을 41개 지점 1회 투영으로 변경 |
| H-3 | 행별 도로 스팬을 로드 시점에 1회 사전 평활화(`_rebuildRowSamples`). 최근접 스팬 탐색은 호출당 O(rows) 선형 검색 → 양방향 스윕 2회로 사전 계산. 샘플링은 배열 2회 읽기 + lerp의 O(1)이 되었고, 셀 내 보간을 유지해 곡률 연속성은 그대로 |
| H-4 | 벽/깃발을 그리드 행 버킷(`_wallsByRow`, `_flagsByRow`)으로 색인. 충돌 판정이 히트박스가 걸치는 행만 조회하도록 변경(약 5,000개 전수 스캔 → 수십 건). 렌더링도 가시 행 범위만 순회하므로 프레임마다 전체 필터·정렬하던 작업 제거 |

추가로 `RacingGame`이 플레이어 기준 도로 지표 4종을 프레임당 1회만 계산하도록 캐시했습니다. 이전에는 모든 투영 호출이 매번 재계산했습니다.

> 시각적 변경: 세그먼트 내부 그라디언트가 단색으로 바뀌었습니다(두 정지점의 중간색 사용). 세그먼트 간 명암 교대와 전체 톤은 유지됩니다.

## 4. 미배선 기능

| 항목 | 조치 |
|---|---|
| M-3 | HUD 좌상단에 일시정지 버튼 추가. `PauseOverlay`와 RESUME/RESTART/HOME 경로가 실제로 도달 가능해짐 |
| M-4 | 동작하지 않던 스킬 버튼 슬롯을 브레이크 버튼으로 전용(누름/뗌 → `brake` start/stop). 조이스틱은 탭만으로도 가속이 걸리도록 `onTapDown` 추가 |
| M-5 | 카운트다운을 실제 시뮬레이션 정지로 변경. `RacingGame.isCountingDown` 동안 연료·충돌·깃발·경과시간·입력이 모두 멈추고, 플레이어/추격차도 이동하지 않음. `StageRun.countdownRemaining`을 신설해 HUD가 경과시간을 역산하지 않도록 함 |

## 5. 밸런스

| 항목 | 조치 |
|---|---|
| M-6 | 미사용 `nitroFuelDrainMultiplier` 제거. 니트로에 1회 연료 비용(`nitroFuelCost`)과 쿨다운(`nitroCooldownSeconds`)을 부과하고, 최고 속도의 1.35배로 상한 적용. 사용 불가 상태에서는 버튼이 흐려짐 |
| M-8 | 점수/코인 산식을 순수 모듈 `RunScoring`으로 분리. 점수 하한 0 적용, 코인을 점수에서 파생시켜 충돌 패널티가 양쪽에 반영되도록 하고, 실패한 런은 50%만 지급. 값과 이름이 어긋나던 `distanceReached`를 `flagsCollected`로 정정 |

## 6. 아키텍처

| 항목 | 조치 |
|---|---|
| M-1 | 모든 입력이 커맨드 스트림 단일 경로를 사용. 속도 상한 로직의 중복 분기를 `_capSpeed()` 하나로 정리(동작 동일) |
| M-2 | 배경 패럴랙스를 Flame `Backdrop` 컴포넌트로 이관. 60fps `AnimationController` 재빌드와 `_GameplayParallaxBackground` 약 110줄 제거. `BoxFit.cover` 동작은 소스 렉트 계산으로 재현 |
| M-7 | 결과 보고 직전에 최종 상태를 강제 flush. 결과 화면이 최대 100ms 낡은 스냅샷을 쓰던 문제 해소. `activeRun`이 null이어도 결과 화면으로 진행하도록 수정(이전에는 게임플레이 화면에 갇힘) |

## 7. 테스트

| 항목 | 조치 |
|---|---|
| L-8 | 빈 껍데기 5건과 동어반복 레이아웃 테스트를 삭제하고 실효 테스트로 교체 |

- `run_scoring_test.dart` — 점수 하한, 충돌 패널티, 성공/실패 지급률
- `stage_layout_test.dart` — 파싱, 도로 스팬 산출, 스팬 내부 벽 필터링, 범위 클램프, 스테이지 번호 해석, 에셋 경로
- `vehicle_spec_test.dart` — 레벨 1/10 경계, 범위 밖 클램프, 단조성, 카탈로그 불변식
- `app_state_controller_test.dart` — 구매 실패/성공/중복, 미보유 선택 무시, 저장소 왕복
- `gameplay_hud_test.dart` — 연료·속도·랩 표시, 연료 경고색 전이, 카운트다운 표시 조건, 잔기 하트, 일시정지 커맨드 발신

## 8. 정리

| 항목 | 조치 |
|---|---|
| L-1 | 한 번도 실행되지 않던 청크 스트리밍 로직 삭제. 스테이지 전체를 로드 시점에 구성 |
| L-2 | `viewportInWorld`, `normalizedStageX`, `worldRenderOffset`, `collectedFlags`, 빈 `_renderBackdrop`, `RunStatus.paused`/`.exited` 제거 |
| L-3 | 항등 함수였던 `pow(t, 1.0)` 제거 |
| L-4 | `_NitroButton`, `_SkillButton`, `_JoystickPanel` 래퍼 삭제. `_ActionButton`에 라벨/활성 상태 지원을 넣어 통합 |
| L-5 | `Offset2`와 미사용 `playerPosition` 필드 제거 |
| L-6 | `CameraCenteredGame`/`Stage`/`Player`/`Chaser` → `RacingGame`/`Stage`/`Player`/`Chaser`. 파일명도 함께 변경(`git mv`로 이력 보존) |
| L-7 | 프로필 디코드 실패 시 `debugPrint`로 사유 기록. `schemaVersion` 필드 추가. 숫자 필드가 double/string으로 저장돼도 견디도록 파싱 완화. 카탈로그에 기본 해금 차량이 없을 때 `owned.first`가 던지던 문제 방어 |

## 남은 판단 사항

- **니트로 상한 도달 시 비용 부과**: 이미 상한 속도인 상태에서 니트로를 누르면 연료와 쿨다운은 소모되지만 가속은 없습니다. 발생 조건이 좁아 그대로 두었습니다
- **도로 렌더 색상**: 위에 적은 대로 세그먼트 내부 그라디언트가 단색으로 바뀌었습니다. 원래의 미세한 밴딩이 필요하면 전체 스트립에 셰이더 1개를 캐시하는 방식으로 되살릴 수 있습니다
- **스테이지 상단 랩 경계**: 도로 형상은 래핑되지만 나무/벽 오브젝트는 래핑되지 않아, 스테이지 최상단에서는 전방에 오브젝트가 비어 보입니다. 기존 동작이라 유지했습니다

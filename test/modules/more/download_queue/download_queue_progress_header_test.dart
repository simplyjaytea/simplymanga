import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/modules/more/download_queue/download_queue_progress_header.dart';
import 'package:mangayomi/services/download_manager/download_queue_progress.dart';
import 'package:shiori/shiori.dart';

/// D3: the queue's aggregate progress header is crease-aware. On the inner
/// portrait display the counts sit in the left room and the bar in the right,
/// with nothing — no text, icon or bar — over the 32pt hinge band [297,329].
/// On every other posture it is one compact row. A fold changes the layout
/// without losing the progress being shown, and a noisy posture stream is
/// debounced (120ms) before anything moves.
void main() {
  const innerPortrait = Size(626, 890);
  const cover = Size(390, 844);
  const coverLandscape = Size(678, 466);
  const innerLandscape = Size(890, 626);

  DownloadQueueProgress progress({
    int active = 3,
    int waiting = 5,
    double fraction = 0.25,
    bool paused = false,
  }) => DownloadQueueProgress(
    activeCount: active,
    waitingCount: waiting,
    overallFraction: fraction,
    paused: paused,
  );

  Future<void> pumpHeader(
    WidgetTester tester, {
    required FoldStateDriver driver,
    required Size size,
    DownloadQueueProgress? value,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildShioriTheme(
          brightness: Brightness.dark,
          colors: FlexColor.schemesList[2].dark,
          tintSurfaces: false,
          blendLevel: 10,
          density: ShioriDensity.phone,
        ),
        home: FoldAwareShell(
          driver: driver,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: DownloadQueueProgressHeader(
                progress: value ?? progress(),
                semanticLabel: 'Download queue',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Every piece of content the header renders — text, icons, the bar — must
  /// stay out of the crease band. Containers may span it; content may not.
  void expectContentClearOfBand(WidgetTester tester, Rect band) {
    for (final finder in [
      find.byType(Text),
      find.byType(Icon),
      find.byType(ShioriProgressBar),
    ]) {
      for (final element in finder.evaluate()) {
        final box = element.renderObject as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        expect(
          rect.overlaps(band),
          isFalse,
          reason: '$rect intersects the crease band $band',
        );
      }
    }
  }

  testWidgets('inner portrait keeps counts and bar in their own rooms', (
    tester,
  ) async {
    await pumpHeader(
      tester,
      driver: FakeFoldStateDriver(FoldState.innerPortrait),
      size: innerPortrait,
    );

    const band = Rect.fromLTRB(297, 0, 329, 890);
    expectContentClearOfBand(tester, band);

    // Counts in the left room [16,281], bar in the right room [345,610].
    final activeCount = rectOf(tester, find.text('3'));
    final waitingCount = rectOf(tester, find.text('5'));
    final bar = rectOf(tester, find.byType(ShioriProgressBar));
    expect(activeCount.right, lessThanOrEqualTo(281));
    expect(waitingCount.right, lessThanOrEqualTo(281));
    expect(bar.left, greaterThanOrEqualTo(345));
    expect(bar.right, lessThanOrEqualTo(610));
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('cover is one compact row with no crease split', (tester) async {
    await pumpHeader(
      tester,
      driver: FakeFoldStateDriver(FoldState.cover),
      size: cover,
    );

    final bar = rectOf(tester, find.byType(ShioriProgressBar));
    final percent = rectOf(tester, find.text('25%'));
    // A single row: the bar starts well left of where the inner split would
    // put it, and everything fits the cover width.
    expect(bar.left, lessThan(200));
    expect(percent.right, lessThanOrEqualTo(390 - 16));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('cover landscape stays a compact row that fits', (tester) async {
    await pumpHeader(
      tester,
      driver: FakeFoldStateDriver(FoldState.cover),
      size: coverLandscape,
    );

    final bar = rectOf(tester, find.byType(ShioriProgressBar));
    final percent = rectOf(tester, find.text('25%'));
    expect(bar.left, lessThan(200));
    expect(percent.right, lessThanOrEqualTo(678 - 16));
  });

  testWidgets('inner landscape keeps the header above the horizontal crease', (
    tester,
  ) async {
    await pumpHeader(
      tester,
      driver: FakeFoldStateDriver(FoldState.innerLandscape),
      size: innerLandscape,
    );

    const band = Rect.fromLTRB(0, 297, 890, 329);
    expectContentClearOfBand(tester, band);
    final header = rectOf(tester, find.byType(DownloadQueueProgressHeader));
    expect(header.bottom, lessThanOrEqualTo(297));
  });

  testWidgets('a fold relayouts without losing the progress shown', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    await pumpHeader(tester, driver: driver, size: cover);
    expect(find.text('25%'), findsOneWidget);

    // Unfold to the inner display: the viewport grows and the posture settles
    // to inner portrait — same data, split rooms.
    tester.view.physicalSize = innerPortrait;
    driver.report(FoldState.innerPortrait);
    await tester.pumpAndSettle();

    expect(find.text('25%'), findsOneWidget);
    final bar = rectOf(tester, find.byType(ShioriProgressBar));
    expect(bar.left, greaterThanOrEqualTo(345));
  });

  testWidgets('progress updates rebuild the counts and the bar', (tester) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    await pumpHeader(tester, driver: driver, size: cover);
    expect(find.text('25%'), findsOneWidget);

    await pumpHeader(
      tester,
      driver: driver,
      size: cover,
      value: progress(active: 1, waiting: 2, fraction: 0.6),
    );

    expect(find.text('25%'), findsNothing);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a paused queue shows the pause glyph instead of downloading', (
    tester,
  ) async {
    await pumpHeader(
      tester,
      driver: FakeFoldStateDriver(FoldState.cover),
      size: cover,
      value: progress(paused: true),
    );

    expect(find.byIcon(Symbols.pause), findsOneWidget);
    expect(find.byIcon(Symbols.downloading), findsNothing);
  });

  testWidgets('a noisy posture stream is debounced for 120ms before layout', (
    tester,
  ) async {
    final driver = FoldStateController(initialState: FoldState.cover);
    addTearDown(driver.dispose);
    await pumpHeader(tester, driver: driver, size: innerPortrait);

    // Cover layout while the posture is still settling.
    expect(
      rectOf(tester, find.byType(ShioriProgressBar)).left,
      lessThan(200),
    );

    driver.report(FoldState.innerPortrait);
    await tester.pump(const Duration(milliseconds: 119));
    // Not settled yet: still the compact row.
    expect(
      rectOf(tester, find.byType(ShioriProgressBar)).left,
      lessThan(200),
    );

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    // Settled: the bar moved into the right room, clear of the crease.
    expect(
      rectOf(tester, find.byType(ShioriProgressBar)).left,
      greaterThanOrEqualTo(345),
    );
  });
}

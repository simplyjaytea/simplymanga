import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/crease_rooms.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';

void main() {
  const innerPortrait = Size(626, 890);
  const innerLandscape = Size(890, 626);
  const cover = Size(390, 844);
  const coverLandscape = Size(678, 466);
  const portraitBand = Rect.fromLTRB(297, 0, 329, 890);

  FoldReaderRooms roomsFor(FoldState state, Size size) => FoldReaderRooms(
    spec: FoldLayoutSpec.resolve(foldState: state, size: size),
    viewport: size,
  );

  bool clearsBand(Rect room, Rect? band) =>
      band == null ||
      room.right <= band.left ||
      room.left >= band.right ||
      room.bottom <= band.top ||
      room.top >= band.bottom;

  group('FoldReaderRooms geometry', () {
    test('inner portrait single page LTR uses the right room', () {
      final rooms = roomsFor(FoldState.innerPortrait, innerPortrait);
      expect(rooms.creaseBand, portraitBand);
      expect(rooms.verticalBand, isTrue);
      expect(
        rooms.singlePageRoom(rtl: false),
        const Rect.fromLTRB(329, 0, 626, 890),
      );
      expect(
        rooms.singlePageRoom(rtl: true),
        const Rect.fromLTRB(0, 0, 297, 890),
      );
      expect(clearsBand(rooms.singlePageRoom(rtl: false), portraitBand), isTrue);
      expect(clearsBand(rooms.singlePageRoom(rtl: true), portraitBand), isTrue);
    });

    test('inner portrait spread rooms flank the 32pt band', () {
      final rooms = roomsFor(FoldState.innerPortrait, innerPortrait);
      final (left, right) = rooms.spreadRooms();
      expect(left, const Rect.fromLTRB(0, 0, 297, 890));
      expect(right, const Rect.fromLTRB(329, 0, 626, 890));
      expect(rooms.spreadGutter, 32);
      expect(clearsBand(left, portraitBand), isTrue);
      expect(clearsBand(right, portraitBand), isTrue);
    });

    test('inner landscape single page uses the bottom room', () {
      final rooms = roomsFor(FoldState.innerLandscape, innerLandscape);
      expect(rooms.verticalBand, isFalse);
      expect(
        rooms.singlePageRoom(rtl: false),
        const Rect.fromLTRB(0, 329, 890, 626),
      );
      expect(
        clearsBand(rooms.singlePageRoom(rtl: false), rooms.creaseBand),
        isTrue,
      );
    });

    test('inner landscape spread splits the bottom room', () {
      final rooms = roomsFor(FoldState.innerLandscape, innerLandscape);
      final (left, right) = rooms.spreadRooms();
      expect(left, const Rect.fromLTRB(0, 329, 445, 626));
      expect(right, const Rect.fromLTRB(445, 329, 890, 626));
      expect(rooms.spreadGutter, 0);
      expect(clearsBand(left, rooms.creaseBand), isTrue);
      expect(clearsBand(right, rooms.creaseBand), isTrue);
    });

    test('cover postures keep the full viewport', () {
      for (final size in [cover, coverLandscape]) {
        final rooms = roomsFor(FoldState.cover, size);
        expect(rooms.hasBand, isFalse);
        expect(rooms.singlePageRoom(rtl: false), Offset.zero & size);
        final (left, right) = rooms.spreadRooms();
        expect(left.width + right.width, size.width);
        expect(left.height, size.height);
        expect(rooms.spreadGutter, 0);
      }
    });

    test('unknown posture never invents a band', () {
      final rooms = roomsFor(FoldState.unknown, innerPortrait);
      expect(rooms.hasBand, isFalse);
      expect(rooms.singlePageRoom(rtl: false), Offset.zero & innerPortrait);
    });

    test('half-open tall behaves like inner portrait', () {
      final rooms = roomsFor(FoldState.halfOpen, innerPortrait);
      expect(rooms.verticalBand, isTrue);
      expect(
        rooms.singlePageRoom(rtl: false),
        const Rect.fromLTRB(329, 0, 626, 890),
      );
    });
  });

  group('CreaseRoomBox', () {
    testWidgets('positions the child exactly inside the room', (tester) async {
      tester.view.physicalSize = innerPortrait;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rooms = roomsFor(FoldState.innerPortrait, innerPortrait);
      await tester.pumpWidget(
        MaterialApp(
          home: CreaseRoomBox(
            viewport: innerPortrait,
            room: rooms.singlePageRoom(rtl: false),
            child: const SizedBox.expand(key: ValueKey('page')),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('page'))),
        const Rect.fromLTRB(329, 0, 626, 890),
      );
    });

    testWidgets('full-viewport room keeps the bare-child geometry', (
      tester,
    ) async {
      tester.view.physicalSize = cover;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: CreaseRoomBox(
            viewport: cover,
            room: Offset.zero & cover,
            child: const SizedBox.expand(key: ValueKey('page')),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('page'))),
        Offset.zero & cover,
      );
    });

    testWidgets('fold settle moves the page between rooms', (tester) async {
      tester.view.physicalSize = cover;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FoldAwareShell(
            driver: driver,
            child: Builder(
              builder: (context) {
                final spec = FoldLayoutScope.of(context);
                final size = MediaQuery.sizeOf(context);
                final rooms = FoldReaderRooms(spec: spec, viewport: size);
                return CreaseRoomBox(
                  viewport: size,
                  room: rooms.singlePageRoom(rtl: false),
                  child: const SizedBox.expand(key: ValueKey('page')),
                );
              },
            ),
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('page'))),
        Offset.zero & cover,
      );

      tester.view.physicalSize = innerPortrait;
      driver.report(FoldState.innerPortrait);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        tester.getRect(find.byKey(const ValueKey('page'))),
        const Rect.fromLTRB(329, 0, 626, 890),
      );
    });
  });
}

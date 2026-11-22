import 'dart:convert';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_connection_screen.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';
import 'package:shiori/shiori.dart';

class _MemoryStore implements AbsCredentialsStore {
  _MemoryStore([this.saved]);

  AbsCredentials? saved;
  int clears = 0;

  @override
  Future<AbsCredentials?> read() async => saved;

  @override
  Future<void> save(AbsCredentials credentials) async => saved = credentials;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

Widget _app({
  required AbsCredentialsStore store,
  required Future<http.Response> Function(http.Request) handler,
}) {
  return ProviderScope(
    overrides: [
      absCredentialsStoreProvider.overrideWithValue(store),
      absClientFactoryProvider.overrideWithValue(
        (credentials) => AudiobookshelfClient(
          baseUrl: credentials.baseUrl,
          token: credentials.token,
          httpClient: MockClient(handler),
        ),
      ),
    ],
    child: MaterialApp(
      theme: buildShioriTheme(
        brightness: Brightness.dark,
        colors: FlexColor.schemesList[2].dark,
        tintSurfaces: false,
        blendLevel: 10,
        density: ShioriDensity.phone,
      ),
      home: const AudiobookshelfConnectionScreen(),
    ),
  );
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  testWidgets('starts empty with the test and save actions disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        store: _MemoryStore(),
        handler: (_) async => _json({'success': true}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Audiobookshelf'), findsOneWidget);
    expect(find.byKey(const Key('abs-url')), findsOneWidget);
    expect(find.byKey(const Key('abs-token')), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Save & connect'), findsOneWidget);

    final testerButton = tester.widget<ShioriButton>(
      find.byKey(const Key('abs-test')),
    );
    final saveButton = tester.widget<ShioriButton>(
      find.byKey(const Key('abs-save')),
    );
    expect(testerButton.onPressed, isNull);
    expect(saveButton.onPressed, isNull);
  });

  testWidgets('a successful test names the account', (tester) async {
    await tester.pumpWidget(
      _app(
        store: _MemoryStore(),
        handler: (request) async => switch (request.url.path) {
          '/ping' => _json({'success': true}),
          '/api/me' => _json({'id': 'u1', 'username': 'ada'}),
          _ => _json({}, 404),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('abs-url')),
      'http://host:13378',
    );
    await tester.enterText(find.byKey(const Key('abs-token')), 'tok');
    await tester.pump();
    await tester.tap(find.byKey(const Key('abs-test')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected as ada'), findsOneWidget);
  });

  testWidgets('a rejected token is shown, not swallowed', (tester) async {
    await tester.pumpWidget(
      _app(
        store: _MemoryStore(),
        handler: (request) async => request.url.path == '/ping'
            ? _json({'success': true})
            : _json({'error': 'Unauthorized'}, 401),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('abs-url')),
      'http://host:13378',
    );
    await tester.enterText(find.byKey(const Key('abs-token')), 'wrong');
    await tester.pump();
    await tester.tap(find.byKey(const Key('abs-test')));
    await tester.pumpAndSettle();

    expect(find.textContaining('rejected the token'), findsOneWidget);
  });

  testWidgets('save persists the normalized URL and token', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      _app(store: store, handler: (_) async => _json({'success': true})),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('abs-url')),
      'http://host:13378/',
    );
    await tester.enterText(find.byKey(const Key('abs-token')), 'tok');
    await tester.pump();
    await tester.tap(find.byKey(const Key('abs-save')));
    await tester.pumpAndSettle();

    expect(store.saved?.baseUrl, 'http://host:13378');
    expect(store.saved?.token, 'tok');
  });

  testWidgets('stored credentials fill the fields and offer disconnect', (
    tester,
  ) async {
    final store = _MemoryStore(
      const AbsCredentials(baseUrl: 'http://host:13378', token: 'tok'),
    );
    await tester.pumpWidget(
      _app(store: store, handler: (_) async => _json({'success': true})),
    );
    await tester.pumpAndSettle();

    expect(find.text('http://host:13378'), findsOneWidget);
    expect(find.byKey(const Key('abs-disconnect')), findsOneWidget);

    await tester.tap(find.byKey(const Key('abs-disconnect')));
    await tester.pumpAndSettle();

    expect(store.clears, 1);
    expect(find.byKey(const Key('abs-disconnect')), findsNothing);
  });
}

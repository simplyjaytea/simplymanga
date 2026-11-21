import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/host_health.dart';
import 'package:mangayomi/repositories/host_health_repository.dart';
import 'package:mangayomi/src/rust/api/anime_engine.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    try {
      await Isar.initializeIsarCore(download: true);
    } finally {
      HttpOverrides.global = overrides;
    }
  });

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('host_health');
    isar = await Isar.open(
      [HostHealthSchema],
      directory: directory.path,
      name: 'host_health_${directory.path.hashCode}',
    );
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  const view = HostHealthView(
    host: 'https://server.example/stream',
    successEwma: 0.82,
    latencyEwmaMs: 240.5,
    samples: 7,
    challenges: 1,
  );

  test('a snapshot reads back every field it was saved with', () async {
    await hostHealthRepository.saveSnapshot([view]);
    final all = hostHealthRepository.getAll();
    expect(all, hasLength(1));
    final row = all.single;
    expect(row.host, view.host);
    expect(row.successEwma, 0.82);
    expect(row.latencyEwmaMs, 240.5);
    expect(row.samples, 7);
    expect(row.challenges, 1);
    expect(row.updatedAt, greaterThan(0));
  });

  test('getByHost finds the row for one host', () async {
    await hostHealthRepository.saveSnapshot([view]);
    final row = hostHealthRepository.getByHost(view.host);
    expect(row, isNotNull);
    expect(row!.successEwma, 0.82);
    expect(hostHealthRepository.getByHost('https://absent.example'), isNull);
  });

  test('saving the same host again upserts rather than duplicating', () async {
    await hostHealthRepository.saveSnapshot([view]);
    const updated = HostHealthView(
      host: 'https://server.example/stream',
      successEwma: 0.3,
      latencyEwmaMs: 999,
      samples: 9,
      challenges: 2,
    );
    await hostHealthRepository.saveSnapshot([updated]);
    final all = hostHealthRepository.getAll();
    expect(all, hasLength(1));
    expect(all.single.successEwma, 0.3);
    expect(all.single.samples, 9);
  });

  test('an empty snapshot is a no-op', () async {
    await hostHealthRepository.saveSnapshot([view]);
    await hostHealthRepository.saveSnapshot(const []);
    expect(hostHealthRepository.getAll(), hasLength(1));
  });

  test('clear empties the store', () async {
    await hostHealthRepository.saveSnapshot([view]);
    await hostHealthRepository.clear();
    expect(hostHealthRepository.getAll(), isEmpty);
  });
}
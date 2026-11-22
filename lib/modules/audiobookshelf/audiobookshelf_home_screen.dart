import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';

import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_connection_screen.dart';
import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_library_screen.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';

/// The `/audiobookshelf` page: setup until a server is saved, then the
/// library. Keeping both behind one route means the More tile has one place to
/// go whether or not this device has connected before.
class AudiobookshelfHomeScreen extends ConsumerWidget {
  const AudiobookshelfHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(absSettingsProvider);
    return settings.when(
      loading: () => const Scaffold(body: ShioriLoading()),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Audiobookshelf')),
        body: ShioriErrorState(
          title: 'Could not read the Audiobookshelf settings',
          detail: '$error',
          retryLabel: 'Retry',
          onRetry: () => ref.invalidate(absSettingsProvider),
        ),
      ),
      data: (credentials) => credentials == null
          ? const AudiobookshelfConnectionScreen()
          : const AudiobookshelfLibraryScreen(),
    );
  }
}

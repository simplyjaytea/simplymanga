import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';

import 'package:mangayomi/modules/audiobookshelf/audiobookshelf_shared.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_client.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_models.dart';
import 'package:mangayomi/services/audiobookshelf/audiobookshelf_settings.dart';
import 'package:mangayomi/utils/platform_utils.dart';

final absLibrariesProvider = FutureProvider.autoDispose<List<AbsLibrary>>((
  ref,
) async {
  final client = ref.watch(absClientProvider);
  if (client == null) {
    throw const AbsUnreachableException('No Audiobookshelf server is saved.');
  }
  return client.libraries();
});

/// The library tab: first the server's book libraries, then one library's
/// books, paged. Non-book libraries are listed but dimmed: the app cannot play
/// podcasts yet, and hiding them would make a server look half-empty.
class AudiobookshelfLibraryScreen extends ConsumerStatefulWidget {
  const AudiobookshelfLibraryScreen({super.key});

  @override
  ConsumerState<AudiobookshelfLibraryScreen> createState() =>
      _AudiobookshelfLibraryScreenState();
}

class _AudiobookshelfLibraryScreenState
    extends ConsumerState<AudiobookshelfLibraryScreen> {
  AbsLibrary? _library;
  final List<AbsLibraryItem> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loadingItems = false;
  bool _loadingMore = false;
  String? _itemsError;

  bool get _hasMore => _items.length < _total;

  void _openLibrary(AbsLibrary library) {
    if (!library.isBooks) return;
    setState(() {
      _library = library;
      _items.clear();
      _page = 0;
      _total = 0;
      _itemsError = null;
    });
    _loadPage(0);
  }

  void _backToLibraries() {
    setState(() {
      _library = null;
      _items.clear();
      _itemsError = null;
    });
  }

  Future<void> _loadPage(int page) async {
    final library = _library;
    final client = ref.read(absClientProvider);
    if (library == null || client == null) return;
    setState(() {
      if (page == 0) {
        _loadingItems = true;
        _itemsError = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final result = await client.libraryItems(library.id, page: page);
      if (!mounted) return;
      setState(() {
        if (page == 0) _items.clear();
        _items.addAll(result.items);
        _page = result.page;
        _total = result.total;
        _itemsError = null;
      });
    } on AbsException catch (error) {
      if (!mounted) return;
      setState(() => _itemsError = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _loadingItems = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (_library == null) {
      ref.invalidate(absLibrariesProvider);
      return;
    }
    await _loadPage(0);
  }

  @override
  Widget build(BuildContext context) {
    // A different server (or token) means the list on screen belongs to
    // another library: drop back to the library picker.
    ref.listen(absClientProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _library = null;
        _items.clear();
        _page = 0;
        _total = 0;
        _itemsError = null;
      });
    });
    final libraries = ref.watch(absLibrariesProvider);
    final library = _library;
    return Scaffold(
      appBar: AppBar(
        leading: library == null
            ? null
            : IconButton(
                tooltip: 'Libraries',
                icon: const Icon(Symbols.arrow_back_rounded),
                onPressed: _backToLibraries,
              ),
        title: Text(library?.name ?? 'Audiobookshelf'),
        actions: [
          IconButton(
            tooltip: 'Server settings',
            icon: const Icon(Symbols.settings_rounded),
            onPressed: () => context.push('/audiobookshelfSetup'),
          ),
        ],
      ),
      body: library == null
          ? _LibrariesBody(
              libraries: libraries,
              onOpen: _openLibrary,
              onRetry: () => ref.invalidate(absLibrariesProvider),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: _LibraryItemsBody(
                items: _items,
                loading: _loadingItems,
                loadingMore: _loadingMore,
                hasMore: _hasMore,
                error: _itemsError,
                onRetry: () => _loadPage(_items.isEmpty ? 0 : _page + 1),
                onLoadMore: () => _loadPage(_page + 1),
                onOpen: (item) =>
                    context.push('/audiobookshelfPlayer', extra: item),
              ),
            ),
    );
  }
}

class _LibrariesBody extends StatelessWidget {
  const _LibrariesBody({
    required this.libraries,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<List<AbsLibrary>> libraries;
  final ValueChanged<AbsLibrary> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return libraries.when(
      loading: () => const ShioriLoading(label: 'Loading libraries…'),
      error: (error, _) => ShioriErrorState(
        title: 'Could not load libraries',
        detail: error is AbsException ? error.message : '$error',
        retryLabel: 'Retry',
        onRetry: onRetry,
      ),
      data: (all) {
        if (all.isEmpty) {
          return ShioriEmptyState(
            icon: Symbols.library_books_rounded,
            title: 'No libraries',
            message:
                'This server has no libraries yet. Create one in Audiobookshelf '
                'first, then come back.',
            actionLabel: 'Retry',
            onAction: onRetry,
          );
        }
        final books = all.where((library) => library.isBooks).length;
        return ListView(
          padding: pageInsets(context),
          children: [
            if (books == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ShioriSpace.s16,
                  ShioriSpace.s8,
                  ShioriSpace.s16,
                  ShioriSpace.s8,
                ),
                child: Text(
                  'No library here holds audiobooks. Only book libraries can '
                  'be played.',
                  style: context.shiori.text.meta.copyWith(
                    color: context.shiori.color.fgMuted,
                  ),
                ),
              ),
            for (final library in all)
              ShioriListRow(
                leading: Icon(
                  library.isBooks
                      ? Symbols.library_books_rounded
                      : Symbols.podcasts_rounded,
                  color: library.isBooks
                      ? context.shiori.color.accentInk
                      : context.shiori.color.fgMuted,
                ),
                title: library.name,
                subtitle: library.isBooks
                    ? 'Audiobooks'
                    : '${library.mediaType} — not playable here',
                dimmed: !library.isBooks,
                trailing: library.isBooks
                    ? const Icon(Symbols.chevron_right_rounded)
                    : null,
                onTap: library.isBooks ? () => onOpen(library) : null,
              ),
          ],
        );
      },
    );
  }
}

class _LibraryItemsBody extends StatelessWidget {
  const _LibraryItemsBody({
    required this.items,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onRetry,
    required this.onLoadMore,
    required this.onOpen,
  });

  final List<AbsLibraryItem> items;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final ValueChanged<AbsLibraryItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading && items.isEmpty) {
      return const ShioriLoading(label: 'Loading books…');
    }
    if (error != null && items.isEmpty) {
      return ShioriErrorState(
        title: 'Could not load books',
        detail: error,
        retryLabel: 'Retry',
        onRetry: onRetry,
      );
    }
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: const ShioriEmptyState(
              icon: Symbols.auto_stories_rounded,
              title: 'No books yet',
              message: 'This library has no audiobooks to play.',
            ),
          ),
        ],
      );
    }
    final trailingRows = (hasMore || error != null) ? 1 : 0;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: pageInsets(context),
      itemCount: items.length + trailingRows,
      itemBuilder: (context, index) {
        if (index == items.length) {
          if (error != null) {
            return Padding(
              padding: const EdgeInsets.all(ShioriSpace.s16),
              child: ShioriButton.secondary(
                label: 'Try again',
                onPressed: loadingMore ? null : onRetry,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(ShioriSpace.s16),
            child: ShioriButton.secondary(
              label: loadingMore ? 'Loading…' : 'Load more',
              loading: loadingMore,
              onPressed: loadingMore ? null : onLoadMore,
            ),
          );
        }
        final item = items[index];
        return ShioriListRow(
          leading: ShioriThumbnail(height: 64, child: AbsBookCover(item: item)),
          title: item.title,
          titleMaxLines: 2,
          subtitle: absBookSubtitle(
            author: item.author,
            duration: item.duration,
            tracks: item.numTracks,
          ),
          trailing: const Icon(Symbols.chevron_right_rounded),
          onTap: () => onOpen(item),
        );
      },
    );
  }
}

/// The cover for one row, with the token in its URL.
class AbsBookCover extends ConsumerWidget {
  const AbsBookCover({super.key, required this.item});

  final AbsLibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(absClientProvider);
    return AbsCover(uri: client?.coverUri(item.id), title: item.title);
  }
}

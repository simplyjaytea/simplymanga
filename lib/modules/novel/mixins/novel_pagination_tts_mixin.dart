import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/novel/novel_reader_controller_provider.dart';
import 'package:mangayomi/modules/novel/tts/novel_tts_service.dart';
import 'package:mangayomi/core/fold/crease_rooms.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/modules/novel/utils/novel_paginator.dart';
import 'package:mangayomi/modules/novel/utils/settled_pagination.dart';
import 'package:mangayomi/modules/novel/widgets/novel_html_content.dart';
import 'package:mangayomi/src/rust/api/epub.dart';
import 'package:shiori/shiori.dart';

/// Encapsulates discrete-page/double-page spread pagination caching,
/// mode-transition progress preservation, and Text-to-Speech (TTS)
/// synchronization for the Novel Reader.
mixin NovelPaginationAndTtsMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  // ── Host State Contract ───────────────────────────────────────────────────
  Chapter get chapter;
  EpubNovel? get epubBook;
  NovelReaderController get readerController;
  ScrollController get scrollController;
  StreamController<double> get rebuildDetail;
  double get offset;
  set offset(double value);
  double get maxOffset;
  set maxOffset(double value);
  bool get scrolled;
  set scrolled(bool value);
  bool get scrollRestoreScheduled;
  set scrollRestoreScheduled(bool value);

  // ── Pagination State ──────────────────────────────────────────────────────
  PageMode? lastEffectivePageMode;
  ReaderMode? lastReaderMode;
  late final PageController spreadController = PageController();
  int currentSpreadIndex = 0;
  NovelPaginationResult? cachedPagination;
  final SettledPosturePagination<NovelPaginationResult> _foldPagination =
      SettledPosturePagination<NovelPaginationResult>();

  // ── TTS State ─────────────────────────────────────────────────────────────
  bool get ttsSupported => !Platform.isLinux;
  bool showTts = false;
  String? currentHtmlContent;

  /// How long the current chapter takes to read, worked out once when its
  /// text arrives, for the time left beside the progress slider.
  double? chapterMinutes;
  final ValueNotifier<({int paragraph, int wordStart, int wordEnd})>
  ttsProgress = ValueNotifier((paragraph: -1, wordStart: -1, wordEnd: -1));
  int ttsTotalBlocks = 0;
  StreamSubscription<int>? _ttsIndexSub;
  StreamSubscription<TtsState>? _ttsStateSub;
  StreamSubscription<TtsWordProgress>? _ttsWordSub;

  void initTtsSubscriptions() {
    _ttsIndexSub = NovelTtsService.instance.paragraphIndexStream.listen((i) {
      ttsProgress.value = (paragraph: i, wordStart: -1, wordEnd: -1);
      scrollToTtsParagraph(i);
      if (lastEffectivePageMode == PageMode.doublePage &&
          cachedPagination != null) {
        final targetSpread = cachedPagination!.spreadForBlock(i);
        if (spreadController.hasClients && targetSpread != currentSpreadIndex) {
          currentSpreadIndex = targetSpread;
          spreadController.animateToPage(
            targetSpread,
            duration: ShioriMotion.enter,
            curve: Curves.easeInOut,
          );
        }
      }
    });
    _ttsStateSub = NovelTtsService.instance.stateStream.listen((s) {
      if (s == TtsState.stopped) {
        ttsProgress.value = (paragraph: -1, wordStart: -1, wordEnd: -1);
      }
    });
    _ttsWordSub = NovelTtsService.instance.wordProgressStream.listen((wp) {
      ttsProgress.value = (
        paragraph: wp.paragraphIndex,
        wordStart: wp.startOffset,
        wordEnd: wp.endOffset,
      );
    });
  }

  void updatePaginatedOffsetBeforeDispose(ReaderMode readerMode) {
    if (!readerMode.isContinuous &&
        cachedPagination != null &&
        cachedPagination!.pageCount > 0) {
      final progress = lastEffectivePageMode == PageMode.doublePage
          ? cachedPagination!.progressForSpread(currentSpreadIndex)
          : cachedPagination!.progressForPage(currentSpreadIndex);
      offset = progress * (maxOffset > 0 ? maxOffset : 100);
      maxOffset = (maxOffset > 0 ? maxOffset : 100);
    }
  }

  void disposePaginationAndTts() {
    spreadController.dispose();
    _ttsIndexSub?.cancel();
    _ttsStateSub?.cancel();
    _ttsWordSub?.cancel();
    ttsProgress.dispose();
    NovelTtsService.instance.stop();
  }

  void scrollToTtsParagraph(int index) {
    if (!scrollController.hasClients || ttsTotalBlocks <= 0) return;
    final maxScroll = scrollController.position.maxScrollExtent;
    final targetOffset = (index / ttsTotalBlocks) * maxScroll;
    scrollController.animateTo(
      targetOffset.clamp(0.0, maxScroll),
      duration: ShioriMotion.enter,
      curve: Curves.easeInOut,
    );
  }

  void syncPaginationModeTransition({
    required PageMode effectivePageMode,
    required ReaderMode readerMode,
    required ValueNotifier<bool> autoScroll,
    required VoidCallback stopAutoScroll,
    required VoidCallback startAutoScroll,
  }) {
    final prevEffectiveMode = lastEffectivePageMode ?? effectivePageMode;
    final prevReaderMode = lastReaderMode ?? readerMode;
    if (prevEffectiveMode != effectivePageMode ||
        prevReaderMode != readerMode) {
      if (!readerMode.isContinuous) {
        autoScroll.value = false;
        stopAutoScroll();
        final double progress;
        if (prevReaderMode.isContinuous) {
          progress = maxOffset > 0 ? (offset / maxOffset).clamp(0.0, 1.0) : 0.0;
        } else if (cachedPagination != null &&
            cachedPagination!.pageCount > 0) {
          progress = prevEffectiveMode == PageMode.doublePage
              ? cachedPagination!.progressForSpread(currentSpreadIndex)
              : cachedPagination!.progressForPage(currentSpreadIndex);
        } else {
          progress = maxOffset > 0 ? (offset / maxOffset).clamp(0.0, 1.0) : 0.0;
        }
        cachedPagination = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (cachedPagination != null && spreadController.hasClients) {
            final targetSpread = effectivePageMode == PageMode.doublePage
                ? cachedPagination!.spreadForProgress(progress)
                : cachedPagination!.pageForProgress(progress);
            currentSpreadIndex = targetSpread;
            spreadController.jumpToPage(targetSpread);
          }
        });
      } else {
        final progress =
            cachedPagination != null && cachedPagination!.pageCount > 0
            ? (prevEffectiveMode == PageMode.doublePage
                  ? cachedPagination!.progressForSpread(currentSpreadIndex)
                  : cachedPagination!.progressForPage(currentSpreadIndex))
            : (maxOffset > 0 ? (offset / maxOffset).clamp(0.0, 1.0) : 0.0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (scrollController.hasClients) {
            final targetOffset =
                progress * scrollController.position.maxScrollExtent;
            scrollController.jumpTo(targetOffset);
            if (autoScroll.value) {
              startAutoScroll();
            }
          }
        });
      }
      lastEffectivePageMode = effectivePageMode;
      lastReaderMode = readerMode;
    }
  }

  Widget buildPaginatedSpreadView({
    required PageMode effectivePageMode,
    required String htmlData,
    required int fontSize,
    required double lineHeight,
    required int padding,
    required String? fontFamily,
    required bool removeExtraSpacing,
    required TextAlign textAlignEnum,
    required Color parsedTextColor,
    required Color parsedBackgroundColor,
    required ({int paragraph, int wordStart, int wordEnd}) tts,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDouble = effectivePageMode == PageMode.doublePage;
        final rooms = FoldReaderRooms(
          spec:
              FoldLayoutScope.maybeOf(context)?.spec ??
              FoldLayoutSpec.resolve(
                foldState: FoldState.unknown,
                size: constraints.biggest,
              ),
          viewport: constraints.biggest,
        );
        // AC-7: pagination dimensions come from crease-cleared rooms so text
        // never lands inside the physical band. Non-fold postures keep the
        // legacy full-viewport geometry.
        final double singlePageWidth;
        final double pageHeight;
        final double spreadGutter;
        if (isDouble) {
          if (rooms.hasBand && rooms.verticalBand) {
            spreadGutter = rooms.spreadGutter;
            singlePageWidth = (constraints.maxWidth - spreadGutter) / 2;
            pageHeight = constraints.maxHeight;
          } else if (rooms.hasBand) {
            spreadGutter = 1;
            singlePageWidth = (constraints.maxWidth - 1) / 2;
            pageHeight = constraints.maxHeight - rooms.creaseBand!.bottom;
          } else {
            spreadGutter = 1;
            singlePageWidth = (constraints.maxWidth - 1) / 2;
            pageHeight = constraints.maxHeight;
          }
        } else {
          final room = rooms.singlePageRoom(rtl: false);
          spreadGutter = 0;
          singlePageWidth = room.width;
          pageHeight = room.height;
        }

        final posture =
            FoldLayoutScope.maybeOf(context)?.spec.foldState ??
            FoldState.unknown;
        // M6: live constraints change on every fold-animation frame, so they
        // must not key pagination while a posture is known. Only the settled
        // posture invalidates the cache; unknown posture (no fold channel)
        // keeps the legacy orientation-sensitive key for tablet rotation.
        final postureKey = (
          state: posture,
          isLandscape: posture == FoldState.unknown
              ? constraints.maxWidth > constraints.maxHeight
              : posture == FoldState.innerLandscape,
        );
        final options = (
          html: currentHtmlContent ?? htmlData,
          pageMode: effectivePageMode,
          fontSize: fontSize,
          lineHeight: lineHeight,
          padding: padding,
          fontFamily: fontFamily,
          removeExtraSpacing: removeExtraSpacing,
          textAlign: textAlignEnum,
        );
        final previousPagination = cachedPagination;
        final previousVersion = _foldPagination.version;
        final previousProgress = previousPagination == null
            ? null
            : (lastEffectivePageMode == PageMode.doublePage
                  ? previousPagination.progressForSpread(currentSpreadIndex)
                  : previousPagination.progressForPage(currentSpreadIndex));
        cachedPagination = _foldPagination.resolve(
          posture: postureKey,
          options: options,
          paginate: () => NovelPaginator.paginate(
            htmlContent: htmlData,
            pageWidth: singlePageWidth,
            pageHeight: pageHeight,
            fontSize: fontSize.toDouble(),
            lineHeight: lineHeight,
            padding: padding.toDouble(),
            fontFamily: fontFamily,
            removeExtraSpacing: removeExtraSpacing,
            textAlign: textAlignEnum,
          ),
        );
        if (_foldPagination.version != previousVersion &&
            previousProgress != null) {
          final target = isDouble
              ? cachedPagination!.spreadForProgress(previousProgress)
              : cachedPagination!.pageForProgress(previousProgress);
          currentSpreadIndex = target;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && spreadController.hasClients) {
              spreadController.jumpToPage(target);
            }
          });
        }

        if (!scrollRestoreScheduled) {
          scrollRestoreScheduled = true;
          final progress = double.tryParse(chapter.lastPageRead ?? '') ?? 0.0;
          final targetIndex = isDouble
              ? cachedPagination!.spreadForProgress(progress)
              : cachedPagination!.pageForProgress(progress);
          currentSpreadIndex = targetIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (spreadController.hasClients) {
              spreadController.jumpToPage(targetIndex);
              scrolled = true;
            }
          });
        }

        final pagination = cachedPagination!;
        final totalCount = isDouble
            ? pagination.spreadCount
            : pagination.pageCount;

        final Widget spreadView = Container(
          color: parsedBackgroundColor,
          child: PageView.builder(
            controller: spreadController,
            itemCount: totalCount,
            onPageChanged: (pageIndex) {
              currentSpreadIndex = pageIndex;
              final progress = isDouble
                  ? pagination.progressForSpread(pageIndex)
                  : pagination.progressForPage(pageIndex);
              offset = progress * (maxOffset > 0 ? maxOffset : 100);
              maxOffset = (maxOffset > 0 ? maxOffset : 100);
              readerController.setChapterOffset(offset, maxOffset, true);
              rebuildDetail.add(offset);
            },
            itemBuilder: (context, index) {
              if (isDouble) {
                final leftHtml = pagination.leftPageForSpread(index);
                final rightHtml = pagination.rightPageForSpread(index);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: NovelHtmlContent(
                            htmlData: leftHtml,
                            fontFamily: fontFamily,
                            fontSize: fontSize,
                            lineHeight: lineHeight,
                            padding: padding,
                            textAlign: textAlignEnum,
                            removeExtraSpacing: removeExtraSpacing,
                            textColor: parsedTextColor,
                            backgroundColor: parsedBackgroundColor,
                            showTts: showTts,
                            tts: tts,
                            epubBook: epubBook,
                          ),
                        ),
                      ),
                    ),
                    spreadGutter > 1
                        ? SizedBox(width: spreadGutter)
                        : VerticalDivider(
                            width: 1,
                            thickness: 0.5,
                            color: context.shiori.color.hairline,
                          ),
                    Expanded(
                      child: rightHtml != null
                          ? ClipRect(
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: NovelHtmlContent(
                                  htmlData: rightHtml,
                                  fontFamily: fontFamily,
                                  fontSize: fontSize,
                                  lineHeight: lineHeight,
                                  padding: padding,
                                  textAlign: textAlignEnum,
                                  removeExtraSpacing: removeExtraSpacing,
                                  textColor: parsedTextColor,
                                  backgroundColor: parsedBackgroundColor,
                                  showTts: showTts,
                                  tts: tts,
                                  epubBook: epubBook,
                                ),
                              ),
                            )
                          : Container(color: parsedBackgroundColor),
                    ),
                  ],
                );
              } else {
                final pageHtml = pagination.pageForIndex(index);
                return ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: NovelHtmlContent(
                      htmlData: pageHtml,
                      fontFamily: fontFamily,
                      fontSize: fontSize,
                      lineHeight: lineHeight,
                      padding: padding,
                      textAlign: textAlignEnum,
                      removeExtraSpacing: removeExtraSpacing,
                      textColor: parsedTextColor,
                      backgroundColor: parsedBackgroundColor,
                      showTts: showTts,
                      tts: tts,
                      epubBook: epubBook,
                    ),
                  ),
                );
              }
            },
          ),
        );
        // AC-7: keep text out of the crease band. Single pages move into one
        // room; a horizontal-band spread moves into the bottom room. A
        // vertical-band spread already clears the band via its gutter.
        final band = rooms.creaseBand;
        if (band == null) return spreadView;
        final Rect room;
        if (!isDouble) {
          room = rooms.singlePageRoom(rtl: false);
        } else if (!rooms.verticalBand) {
          room = Rect.fromLTRB(
            0,
            band.bottom,
            constraints.maxWidth,
            constraints.maxHeight,
          );
        } else {
          return spreadView;
        }
        return ColoredBox(
          color: parsedBackgroundColor,
          child: CreaseRoomBox(
            viewport: constraints.biggest,
            room: room,
            child: spreadView,
          ),
        );
      },
    );
  }
}

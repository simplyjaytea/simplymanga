import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';

/// A quiet line under a group: a failed test, a successful one. Kept in one
/// place so the connection and library screens state the same kind of thing
/// the same way.
class AbsNotice extends StatelessWidget {
  const AbsNotice({
    super.key,
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ShioriSpace.s16,
        ShioriSpace.s12,
        ShioriSpace.s16,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: ShioriSpace.s8,
          children: [
            Icon(icon, size: 20, color: color),
            Expanded(
              child: Text(
                message,
                style: tokens.text.meta.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A book cover at 2:3, or the quiet placeholder when the server has no image
/// or it cannot be fetched. The server needs the token in the query, so the
/// caller passes the URL from [AudiobookshelfClient.coverUri].
class AbsCover extends StatelessWidget {
  const AbsCover({super.key, required this.uri, required this.title});

  final Uri? uri;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    final placeholder = ColoredBox(
      color: tokens.color.ink2,
      child: Center(
        child: Icon(
          Symbols.headphones_rounded,
          color: tokens.color.fgMuted,
          size: 24,
        ),
      ),
    );
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ShioriShape.cover),
        child: uri == null
            ? placeholder
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                semanticLabel: title,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}

/// "3 h 12 min", "42 min", "under a minute": the shape a reader can compare at
/// a glance, not a stopwatch.
String formatBookDuration(double seconds) {
  if (seconds <= 0) return 'Unknown length';
  final totalMinutes = (seconds / 60).round();
  if (totalMinutes < 1) return 'Under a minute';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes min';
}

/// The second line of a book row: author, length, file count.
String absBookSubtitle({
  required String author,
  required double duration,
  required int tracks,
}) {
  final parts = [
    if (author.trim().isNotEmpty) author.trim(),
    formatBookDuration(duration),
    if (tracks > 0) '$tracks ${tracks == 1 ? 'file' : 'files'}',
  ];
  return parts.join(' · ');
}

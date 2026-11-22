/// Small, immutable models for the parts of the Audiobookshelf API this slice
/// uses. They are plain classes with `fromJson` constructors: nothing here is
/// persisted, so there is no Isar schema and no generated code.
///
/// Durations are in seconds, as the API sends them.
library;

double _double(Object? value, [double fallback = 0]) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text) ?? fallback,
  _ => fallback,
};

int _int(Object? value, [int fallback = 0]) => switch (value) {
  num number => number.toInt(),
  String text => int.tryParse(text) ?? fallback,
  _ => fallback,
};

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

List<dynamic> _list(Object? value) => value is List ? value : const [];

class AbsUser {
  const AbsUser({required this.id, required this.username, this.email});

  factory AbsUser.fromJson(Map<String, dynamic> json) => AbsUser(
    id: _string(json['id']),
    username: _string(json['username']),
    email: json['email'] is String ? json['email'] as String : null,
  );

  final String id;
  final String username;
  final String? email;

  /// What a connection test can name; some servers leave the username empty.
  String get displayName => username.isNotEmpty ? username : (email ?? id);
}

class AbsLibrary {
  const AbsLibrary({
    required this.id,
    required this.name,
    required this.mediaType,
  });

  factory AbsLibrary.fromJson(Map<String, dynamic> json) => AbsLibrary(
    id: _string(json['id']),
    name: _string(json['name'], 'Untitled library'),
    mediaType: _string(json['mediaType']),
  );

  final String id;
  final String name;

  /// `book`, `podcast`, … Only [AbsLibrary.isBooks] can be played here.
  final String mediaType;

  bool get isBooks => mediaType == 'book';
}

/// One row of `GET /api/libraries/{id}/items`, from its `media` block alone.
class AbsLibraryItem {
  const AbsLibraryItem({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.duration,
    required this.numTracks,
  });

  factory AbsLibraryItem.fromJson(Map<String, dynamic> json) {
    final media = _map(json['media']);
    final metadata = _map(media['metadata']);
    return AbsLibraryItem(
      id: _string(json['id']),
      title: _title(metadata),
      author: _author(metadata),
      coverPath: metadata['coverPath'] is String
          ? metadata['coverPath'] as String
          : null,
      duration: _double(media['duration']),
      numTracks: _int(media['numTracks']),
    );
  }

  final String id;
  final String title;
  final String author;

  /// The server's cover path, when it has one. The image is fetched with
  /// [AudiobookshelfClient.coverUri], not from this path.
  final String? coverPath;

  /// Whole-book duration in seconds.
  final double duration;
  final int numTracks;

  static String _title(Map<String, dynamic> metadata) {
    final title = _string(metadata['title']).trim();
    return title.isEmpty ? 'Untitled' : title;
  }

  static String _author(Map<String, dynamic> metadata) {
    final name = _string(metadata['authorName']).trim();
    if (name.isNotEmpty) return name;
    final authors = _list(metadata['authors'])
        .map((author) => _string(_map(author)['name']).trim())
        .where((name) => name.isNotEmpty);
    return authors.join(', ');
  }
}

/// One audio file of a book.
class AbsTrack {
  const AbsTrack({
    required this.ino,
    required this.contentUrl,
    required this.mimeType,
    required this.duration,
    required this.title,
  });

  factory AbsTrack.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final ino = _string(json['ino']).trim();
    final metadata = _map(json['metadata']);
    final title = _string(metadata['title']).trim();
    return AbsTrack(
      ino: ino,
      contentUrl: _string(json['contentUrl']),
      mimeType: _string(json['mimeType']),
      duration: _double(json['duration']),
      title: title.isNotEmpty
          ? title
          : (ino.isNotEmpty ? 'Track $ino' : 'Track ${index + 1}'),
    );
  }

  final String ino;

  /// Relative, e.g. `/api/items/{id}/file/{ino}`. Resolve it with
  /// [AudiobookshelfClient.streamUri].
  final String contentUrl;
  final String mimeType;

  /// This file's duration in seconds.
  final double duration;
  final String title;
}

/// `GET /api/items/{id}`: the library row plus its tracks.
class AbsItem {
  const AbsItem({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.duration,
    required this.numTracks,
    required this.tracks,
  });

  factory AbsItem.fromJson(Map<String, dynamic> json) {
    final summary = AbsLibraryItem.fromJson(json);
    final media = _map(json['media']);
    final tracks = _list(media['tracks'])
        .whereType<Map<String, dynamic>>()
        .indexed
        .map((entry) => AbsTrack.fromJson(entry.$2, index: entry.$1))
        .toList(growable: false);
    return AbsItem(
      id: summary.id,
      title: summary.title,
      author: summary.author,
      coverPath: summary.coverPath,
      duration: summary.duration,
      numTracks: summary.numTracks == 0 ? tracks.length : summary.numTracks,
      tracks: tracks,
    );
  }

  final String id;
  final String title;
  final String author;
  final String? coverPath;
  final double duration;
  final int numTracks;
  final List<AbsTrack> tracks;
}

/// One page of a library's items. [hasMore] is what the "Load more" button
/// reads.
class AbsItemsPage {
  const AbsItemsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory AbsItemsPage.fromJson(Map<String, dynamic> json) {
    final items = _list(json['results'])
        .whereType<Map<String, dynamic>>()
        .map(AbsLibraryItem.fromJson)
        .toList(growable: false);
    final limit = _int(json['limit'], 50);
    return AbsItemsPage(
      items: items,
      total: _int(json['total'], items.length),
      page: _int(json['page']),
      limit: limit,
    );
  }

  final List<AbsLibraryItem> items;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => (page + 1) * limit < total;
}

/// One file of a playback session, as `POST /api/items/{id}/play` returns it.
class AbsAudioTrack {
  const AbsAudioTrack({
    required this.contentUrl,
    required this.mimeType,
    required this.duration,
    required this.title,
  });

  factory AbsAudioTrack.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final title = _string(json['title']).trim();
    return AbsAudioTrack(
      contentUrl: _string(json['contentUrl']),
      mimeType: _string(json['mimeType']),
      duration: _double(json['duration']),
      title: title.isNotEmpty ? title : 'Track ${index + 1}',
    );
  }

  final String contentUrl;
  final String mimeType;
  final double duration;
  final String title;
}

class AbsPlaybackSession {
  const AbsPlaybackSession({
    required this.id,
    required this.currentTime,
    required this.duration,
    required this.audioTracks,
  });

  factory AbsPlaybackSession.fromJson(Map<String, dynamic> json) {
    final tracks = _list(json['audioTracks'])
        .whereType<Map<String, dynamic>>()
        .indexed
        .map((entry) => AbsAudioTrack.fromJson(entry.$2, index: entry.$1))
        .toList(growable: false);
    return AbsPlaybackSession(
      id: _string(json['id']),
      currentTime: _double(json['currentTime']),
      duration: _double(json['duration']),
      audioTracks: tracks,
    );
  }

  final String id;

  /// Where the server says the user left off, in seconds from the start of
  /// the book.
  final double currentTime;
  final double duration;
  final List<AbsAudioTrack> audioTracks;
}

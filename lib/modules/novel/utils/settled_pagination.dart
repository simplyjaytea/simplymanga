/// Caches expensive pagination until the settled posture or formatting changes.
///
/// Viewport metrics can change on every frame while a fold is moving. Callers
/// deliberately provide the settled posture and non-geometric options here;
/// the pagination closure sees the new dimensions only after the posture settles.
class SettledPosturePagination<T> {
  T? _value;
  Object? _posture;
  Object? _options;
  bool _hasValue = false;
  int version = 0;

  T resolve({
    required Object posture,
    required Object options,
    required T Function() paginate,
  }) {
    if (!_hasValue || posture != _posture || options != _options) {
      _value = paginate();
      _posture = posture;
      _options = options;
      _hasValue = true;
      version++;
    }
    return _value as T;
  }
}

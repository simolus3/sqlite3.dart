/// A sink that allows [add] being called exactly once, and then reports the
/// value of the added event.
final class OnceSink<T extends Object> implements Sink<T> {
  T? value;

  @override
  void add(T data) {
    if (value != null) {
      throw StateError('add called more than once');
    }

    value = data;
  }

  @override
  void close() {
    if (value == null) {
      throw StateError('Must call add before closing.');
    }
  }
}

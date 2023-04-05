import 'dart:async';
import 'dart:indexed_db';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'core.dart';

// Doing KeyRange.only / KeyRange.bound in Dart will look up the factory from
// `window`, but we want to look it up from `self` to support workers.
@JS('IDBKeyRange.only')
external KeyRange keyRangeOnly(dynamic vaue);

@JS('IDBKeyRange.bound')
external KeyRange keyRangeBound(dynamic lower, dynamic higher);

extension ObjectStoreExt on ObjectStore {
  @JS("put")
  external Request _put_1(dynamic value, dynamic key);

  @JS("put")
  external Request _put_2(dynamic value);

  @JS('get')
  external Request getValue(dynamic key);

  /// Creates a request to add a value to this object store.
  ///
  /// This must only be called with native JavaScript objects, as complex Dart
  /// objects aren't serialized here.
  Request putRequestUnsafe(dynamic value, [dynamic key]) {
    if (key != null) {
      return _put_1(value, key);
    }
    return _put_2(value);
  }

  @JS('openCursor')
  external Request openCursorNative(Object? range);

  @JS('openCursor')
  external Request openCursorNative2(Object? range, String direction);
}

extension IndexExt on Index {
  @JS('openKeyCursor')
  external Request openKeyCursorNative();
}

extension RequestExt on Request {
  @JS('result')
  external dynamic get _rawResult;

  /// A [StreamIterator] to asynchronously iterate over a [Cursor].
  ///
  /// Dart provides a streaming view over cursors, but the confusing pause
  /// behavior of `await for` loops and IndexedDB's behavior of closing
  /// transactions that are not immediately used after an event leads to code
  /// that is hard to reason about.
  ///
  /// An explicit pull-based model makes it easy to iterate over values in a
  /// cursor while also being clearer about asynchronous suspensions one might
  /// want to avoid.
  StreamIterator<T> cursorIterator<T extends Cursor>() {
    return _CursorReader(this);
  }

  /// Await this request.
  ///
  /// Unlike the request-to-future API from `dart:indexeddb`, this method
  /// reports a proper error if one occurs. Further, there's the option of not
  /// deserializing IndexedDB objects. When [convertResultToDart] (which
  /// defaults to true) is set to false, the direct JS object stored in an
  /// object store will be loaded. It will not be deserialized into a Dart [Map]
  /// in that case.
  Future<T> completed<T>({bool convertResultToDart = true}) {
    final completer = Completer<T>.sync();

    StreamSubscription<void>? success, error;

    void cancel() {
      success?.cancel();
      error?.cancel();
    }

    success = onSuccess.listen((_) {
      cancel();

      // Wrapping with Future.sync in case the cast fails
      completer.complete(
          Future.sync(() => (convertResultToDart ? result : _rawResult) as T));
    });

    error = onError.listen((event) {
      cancel();
      completer.completeError(error ?? event);
    });

    return completer.future;
  }
}

class _CursorReader<T extends Cursor> implements StreamIterator<T> {
  T? _cursor;
  StreamSubscription<void>? _onSuccess, _onError;

  final Request _cursorRequest;

  _CursorReader(this._cursorRequest);

  @override
  Future<void> cancel() async {
    unawaited(_onSuccess?.cancel());
    unawaited(_onError?.cancel());

    _onSuccess = null;
    _onError = null;
  }

  @override
  T get current => _cursor ?? (throw StateError('Await moveNext() first'));

  @override
  Future<bool> moveNext() {
    assert(_onSuccess == null && _onError == null, 'moveNext() called twice');
    _cursor?.next();

    final completer = Completer<bool>.sync();
    _onSuccess = _cursorRequest.onSuccess.listen((event) {
      cancel();

      _cursor = _cursorRequest._rawResult as T?;
      completer.complete(_cursor != null);
    });

    _onError = _cursorRequest.onSuccess.listen((event) {
      cancel();
      completer.completeError(_cursorRequest.error ?? event);
    });

    return completer.future;
  }
}

extension IdbFactoryOnContext on JsContext {
  @JS()
  external IdbFactory? get indexedDB;
}

extension IdbFactoryExt on IdbFactory {
  @JS('databases')
  external Object _jsDatabases();

  Future<List<DatabaseName>?> databases() async {
    if (!hasProperty(this, 'databases')) {
      return null;
    }
    final jsDatabases = await promiseToFuture<List<dynamic>>(_jsDatabases());
    return jsDatabases.cast<DatabaseName>();
  }
}

@JS()
@anonymous
class DatabaseName {
  external String get name;
  external int get version;
}

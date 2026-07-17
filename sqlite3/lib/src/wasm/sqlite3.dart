import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../implementation/sqlite3.dart';
import '../statement.dart';
import 'bindings.dart';
import 'js_interop.dart';
import 'loader.dart';
import 'wasm_interop.dart';

/// A WebAssembly version of the [CommmonSqlite3] interface.
///
/// This implementation supports the same API as the native version based on
/// `dart:ffi`, but runs in the web.
///
/// {@category wasm}
final class WasmSqlite3 extends Sqlite3Implementation {
  /// Loads a web version of the sqlite3 libraries.
  ///
  /// [source] must be a byte buffer of a `sqlite.wasm` file prepared for this
  /// package. This file can be obtained at the [releases][pkg release] for this
  /// package.
  ///
  /// When the [source] is obtained through a HTTP request, consider directly
  /// using [loadFromUrl] as that method is more efficient.
  ///
  /// [pkg release]: https://github.com/simolus3/sqlite3.dart/releases
  static Future<WasmSqlite3> load(
    Uint8List source, {
    WasmModuleLoader? loader,
  }) {
    final headers = JSObject()..['content-type'] = 'application/wasm'.toJS;

    final fakeResponse = web.Response(
      source.toJS,
      web.ResponseInit(headers: headers),
    );

    return _load(fakeResponse, loader);
  }

  /// Loads a web version of the sqlite3 libraries.
  ///
  /// The native wasm library for sqlite3 is loaded from the [uri] with the
  /// desired [headers] through a `fetch` request.
  ///
  /// [pkg release]: https://github.com/simolus3/sqlite3.dart/releases
  static Future<WasmSqlite3> loadFromUrl(
    Uri uri, {
    Map<String, String>? headers,
    WasmModuleLoader? loader,
  }) {
    return loadFromUrlString(uri.toString());
  }

  /// Loads a web version of the sqlite3 libraries.
  ///
  /// The native wasm library for sqlite3 is loaded from the [url] with the
  /// desired [headers] through a `fetch` request.
  ///
  /// Using this over [loadFromUrl] might reduce compiled JS sizes for apps
  /// which otherwise don't use URLs.
  ///
  /// [pkg release]: https://github.com/simolus3/sqlite3.dart/releases
  static Future<WasmSqlite3> loadFromUrlString(
    String url, {
    Map<String, String>? headers,
    WasmModuleLoader? loader,
  }) async {
    web.RequestInit? options;

    if (headers != null) {
      final headersJs = JSObject();
      headers.forEach((key, value) {
        headersJs[key] = value.toJS;
      });

      options = web.RequestInit(headers: headersJs);
    }

    final jsUri = web.URL(url, (globalContext['location'] as web.URL).href);
    final response = await fetch(jsUri, options).toDart;
    return _load(response, loader);
  }

  static Future<WasmSqlite3> _load(
    web.Response fetchResponse,
    WasmModuleLoader? loader,
  ) async {
    loader ??= WasmModuleLoader();
    final module = await loader.loadModule(fetchResponse);
    final bindings = WasmBindings(module, loader.dartFunctions);

    return WasmSqlite3._(bindings);
  }

  WasmSqlite3._(WasmBindings bindings) : super(WasmSqliteBindings(bindings));
}

/// Web-specific extensions for [RawPreparedStatement], which allows binding
/// and reading big integers directly from JavaScript.
///
/// {@category wasm}
extension WasmRawPreparedStatement on RawPreparedStatement {
  /// Calls `sqlite3_bind_int64` with the 1-based index and the target value.
  void bindJSBigInt(int index, JSBigInt value) {
    final impl = rawStatement as WasmStatement;
    handleBindRc(impl.sqlite3_bind_jsBigInt(index, value));
  }

  /// Calls `sqlite3_bind_int64` with the 1-based index and the target value.
  void bindBigInt(int index, BigInt value) {
    handleBindRc(rawStatement.sqlite3_bind_int64BigInt(index, value));
  }

  /// Calls `sqlite3_column_int64` with the given index.
  ///
  /// Note that this performs no bounds check against [columnCount] in Dart.
  JSBigInt columnJSBigInt(int index) {
    final impl = rawStatement as WasmStatement;
    return impl.sqlite3_column_bigint(index);
  }
}

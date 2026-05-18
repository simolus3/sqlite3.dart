/// Helpers implemented with direct interop to web APIs instead of
/// cross-platform Dart packages or the SDK.
///
/// In compiled web workers, Dart's [Uri.parse] implementation takes up a good
/// chunk of the total file size. By using [URL] directly (which is good enough
/// for our use case), we can avoid that implementation.
///
/// Additionally, we can avoid Dart's utf-8 decoder.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

String pathToAbsoluteAndNormalize(String source) {
  return URL(source, 'file:///').pathname;
}

Iterable<String> pathComponents(String path) {
  return URL(path, 'file:///').pathname.split('/').where((e) => e.isNotEmpty);
}

String utf8Decode(Uint8List bytes) {
  return _decoder.decode(bytes.toJS);
}

final _decoder = TextDecoder();

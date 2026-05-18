/// Path helpers implemented with direct interop to web APIs instead of
/// `package:path`.
///
/// In compiled web workers, Dart's [Uri.parse] implementation takes up a good
/// chunk of the total file size. By using [URL] directly (which is good enough
/// for our use case), we can avoid that implementation.
library;

import 'package:web/web.dart';

String pathToAbsoluteAndNormalize(String source) {
  return URL(source, 'file:///').pathname;
}

Iterable<String> pathComponents(String path) {
  return URL(path, 'file:///').pathname.split('/').where((e) => e.isNotEmpty);
}

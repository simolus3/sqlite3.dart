import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

String pathToAbsoluteAndNormalize(String source) {
  return p.url.normalize('/$source');
}

String utf8Decode(Uint8List bytes) {
  return utf8.decode(bytes);
}

Uint8List utf8Encode(String str) {
  return utf8.encode(str);
}

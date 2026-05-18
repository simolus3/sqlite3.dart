import 'package:path/path.dart' as p;

String pathToAbsoluteAndNormalize(String source) {
  return p.url.normalize('/$source');
}

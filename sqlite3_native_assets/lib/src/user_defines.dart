import 'dart:convert';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart';

/// A mockable wrapper around `HookInputUserDefines`.
sealed class UserDefinesOptions {
  const UserDefinesOptions._();
  factory UserDefinesOptions.fromMap(Map<String, Object?> options) =
      _OptionsFromMap;
  factory UserDefinesOptions.fromHooks(BuildInput input) = _UserDefines;

  Object? operator [](String key);

  String inputPath(String path);

  /// Reads [key] under the expectation that it contains a nested structure.
  ///
  /// Since user-defines passed via the command line are always strings, this
  /// attempts to parse string values as JSON.
  Object? readObject(String key) {
    return switch (this[key]) {
      null => null,
      String s => json.decode(s),
      var other => other,
    };
  }
}

final class _OptionsFromMap extends UserDefinesOptions {
  final Map<String, Object?> options;

  _OptionsFromMap(this.options) : super._();

  @override
  Object? operator [](String key) => options[key];

  @override
  String inputPath(String path) => path;
}

final class _UserDefines extends UserDefinesOptions {
  final BuildInput input;

  _UserDefines(this.input) : super._();

  @override
  Object? operator [](String key) => input.userDefines[key];

  @override
  String inputPath(String path) => absolute(
    normalize(join(input.outputDirectory.path, '../../../../../../', path)),
  );
}

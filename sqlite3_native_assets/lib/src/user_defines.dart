import 'dart:convert';

import 'package:native_assets_cli/native_assets_cli.dart';

/// A mockable wrapper around `HookInputUserDefines`.
sealed class UserDefinesOptions {
  const UserDefinesOptions._();
  factory UserDefinesOptions.fromMap(Map<String, Object?> options) =
      _OptionsFromMap;
  factory UserDefinesOptions.fromHooks(HookInput input) = _UserDefines;

  Object? operator [](String key);

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
}

final class _UserDefines extends UserDefinesOptions {
  final HookInput input;

  _UserDefines(this.input) : super._();

  @override
  Object? operator [](String key) => input.userDefines[key];
}

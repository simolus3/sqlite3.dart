import 'dart:ffi';

import '../common/constants.dart';

const _loadableExtensionEntrypoints = {
  LoadableExtension.spellfix1: 'sqlite3_spellfix_init'
};

class SqliteExtension {
  final String entrypoint;

  Pointer<Void> lookup(DynamicLibrary library) {
    return library.lookup<Void>(entrypoint);
  }

  const SqliteExtension(this.entrypoint);

  factory SqliteExtension.from(LoadableExtension loadableExtension) =>
      SqliteExtension(_loadableExtensionEntrypoints[loadableExtension]!);
}

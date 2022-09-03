import 'dart:ffi';

import 'package:meta/meta.dart';

import '../common/constants.dart';

const _loadableExtensionEntrypoints = {
  LoadableExtension.spellfix1: 'sqlite3_spellfix_init'
};

typedef LibraryProvider = DynamicLibrary Function();

class SqliteExtension {
  ///Entrypoint of extension
  ///In most cases sqlite3_<extension_name>_init
  @internal
  final String entrypoint;

  ///External provided library
  ///If null, library provided in `lookup` will get used
  final LibraryProvider? _libraryProvider;

  //Wether this library is statically linked to the sqlite library
  bool get isStaticallyLinked => _libraryProvider == null;

  Pointer<Void> lookup([DynamicLibrary? library]) {
    assert((_libraryProvider != null) ^ (library != null),
        'Please provide ONE library either in constructor or in lookup call');

    final targetLibrary = library ?? _libraryProvider!.call();
    final ptr = targetLibrary.lookup<Void>(entrypoint);
    return ptr;
  }

  const SqliteExtension._(this.entrypoint, this._libraryProvider);

  factory SqliteExtension.staticallyLinked(
          LoadableExtension loadableExtension) =>
      SqliteExtension._(
          _loadableExtensionEntrypoints[loadableExtension]!, null);

  factory SqliteExtension.fromLibrary(
          String entrypoint, LibraryProvider libraryProvider) =>
      SqliteExtension._(entrypoint, libraryProvider);
}

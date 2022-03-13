import 'dart:math';

import 'file_system.dart';

/// An environment under which sqlite is running on the web.
///
/// As code running under WebAssembly doesn't have acccess to the file system or
/// a random source, this functionality must be injected with a Dart wrapper.
class SqliteEnvironment {
  /// The source of randomness used in sqlite3, such as in the `RANDOM()`
  /// function.
  ///
  /// By default, [Random.secure] is used.
  final Random random;

  /// The file system used by sqlite3.
  ///
  /// By default, an [FileSystem.inMemory] file system is used.
  final FileSystem fileSystem;

  SqliteEnvironment({Random? random, FileSystem? fileSystem})
      : random = random ?? Random.secure(),
        fileSystem = fileSystem ?? FileSystem.inMemory();
}

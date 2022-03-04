import 'dart:math';

import 'file_system.dart';

class SqliteEnvironment {
  final Random random;
  final FileSystem fileSystem;

  SqliteEnvironment({Random? random, FileSystem? fileSystem})
      : random = random ?? Random.secure(),
        fileSystem = fileSystem ?? FileSystem.inMemory();
}

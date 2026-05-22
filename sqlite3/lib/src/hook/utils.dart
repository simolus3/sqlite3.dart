import 'dart:io';

import 'package:path/path.dart' as path;

/// A sink that allows [add] being called exactly once, and then reports the
/// value of the added event.
final class OnceSink<T extends Object> implements Sink<T> {
  T? value;

  @override
  void add(T data) {
    if (value != null) {
      throw StateError('add called more than once');
    }

    value = data;
  }

  @override
  void close() {
    if (value == null) {
      throw StateError('Must call add before closing.');
    }
  }
}

void copyDirectory(Directory source, Directory destination) =>
    source.listSync(recursive: false).forEach((var entity) {
      if (entity is Directory) {
        var newDirectory = Directory(
          path.join(destination.absolute.path, path.basename(entity.path)),
        );
        newDirectory.createSync();

        copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        entity.copySync(
          path.join(destination.path, path.basename(entity.path)),
        );
      }
    });

import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'core.dart';

StorageManager? get storageManager {
  final navigator = getProperty<_Navigator>(self, 'navigator');

  if (hasProperty(navigator, 'storage')) {
    return getProperty(navigator, 'storage');
  }

  return null;
}

@JS()
@staticInterop
class _Navigator {}

@JS()
@staticInterop
class StorageManager {}

@JS()
@staticInterop
class FileSystemHandle {}

@JS()
@staticInterop
class FileSystemDirectoryHandle extends FileSystemHandle {}

@JS()
@staticInterop
class FileSystemFileHandle extends FileSystemHandle {}

@JS()
@staticInterop
class FileSystemSyncAccessHandle {}

@JS()
@anonymous
class _GetFileHandleOptions {
  external factory _GetFileHandleOptions({bool? create});
}

@JS()
@anonymous
class _RemoveEntryOptions {
  external factory _RemoveEntryOptions({bool? recursive});
}

@JS()
@anonymous
class FileSystemReadWriteOptions {
  external factory FileSystemReadWriteOptions({int? at});
}

extension StorageManagerApi on StorageManager {
  @JS('getDirectory')
  external Object _getDirectory();

  Future<FileSystemDirectoryHandle> get directory =>
      promiseToFuture(_getDirectory());
}

extension FileSystemHandleApi on FileSystemHandle {
  String get name => getProperty(this, 'name');

  String get kind => getProperty(this, 'kind');

  bool get isFile => kind == 'file';

  bool get isDirectory => kind == 'directory';
}

extension FileSystemDirectoryHandleApi on FileSystemDirectoryHandle {
  @JS('getFileHandle')
  external Object _getFileHandle(String name, _GetFileHandleOptions options);

  @JS('getDirectoryHandle')
  external Object _getDirectoryHandle(
      String name, _GetFileHandleOptions options);

  @JS('removeEntry')
  external Object _removeEntry(String name, _RemoveEntryOptions options);

  Future<FileSystemFileHandle> openFile(String name, {bool create = false}) {
    return promiseToFuture(
        _getFileHandle(name, _GetFileHandleOptions(create: create)));
  }

  Future<FileSystemDirectoryHandle> getDirectory(String name,
      {bool create = false}) {
    return promiseToFuture(
        _getDirectoryHandle(name, _GetFileHandleOptions(create: create)));
  }

  Future<void> removeEntry(String name, {bool recursive = false}) {
    return promiseToFuture(
        _removeEntry(name, _RemoveEntryOptions(recursive: recursive)));
  }

  Stream<FileSystemHandle> list() {
    return AsyncJavaScriptIteratable<List<Object?>>(this)
        .map((data) => data[1] as FileSystemHandle);
  }

  Stream<FileSystemHandle> getFilesRecursively() async* {
    await for (final entry in list()) {
      if (entry.isFile) {
        yield entry;
      } else if (entry.isDirectory) {
        yield* (entry as FileSystemDirectoryHandle).getFilesRecursively();
      }
    }
  }
}

extension FileSystemFileHandleAPi on FileSystemFileHandle {
  @JS('createSyncAccessHandle')
  external Object _createSyncAccessHandle();

  Future<FileSystemSyncAccessHandle> createSyncAccessHandle() {
    return promiseToFuture(_createSyncAccessHandle());
  }
}

extension FileSystemFileSyncAccessHandleApi on FileSystemSyncAccessHandle {
  @JS()
  external void close();

  @JS()
  external void flush();

  @JS()
  external int read(TypedData buffer, [FileSystemReadWriteOptions? options]);

  @JS()
  external int write(TypedData buffer, [FileSystemReadWriteOptions? options]);

  @JS()
  external void truncate(int newSize);

  @JS()
  external int getSize();
}

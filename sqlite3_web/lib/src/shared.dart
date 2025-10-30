/// Functionality shared between workers and client code.

library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// ignore: implementation_imports
import 'package:sqlite3/src/wasm/js_interop/new_file_system_access.dart';
import 'package:web/web.dart';

/// Checks whether IndexedDB is working in the current browser.
Future<bool> checkIndexedDbSupport() async {
  if (!globalContext.has('indexedDB') ||
      // FileReader needed to read and write blobs efficiently
      !globalContext.has('FileReader')) {
    return false;
  }

  final idb = globalContext['indexedDB'] as IDBFactory;

  try {
    const name = 'drift_mock_db';

    final mockDb = await idb.open(name).completeOpen<IDBDatabase>();
    mockDb.close();
    idb.deleteDatabase(name);
  } catch (error) {
    return false;
  }

  return true;
}

/// Returns whether an drift-wasm database with the given [databaseName] exists.
Future<bool> checkIndexedDbExists(String databaseName) async {
  bool? indexedDbExists;

  try {
    final idb = globalContext['indexedDB'] as IDBFactory;

    final openRequest = idb.open(databaseName, 1);
    openRequest.onupgradeneeded = (IDBVersionChangeEvent event) {
      // If there's an upgrade, we're going from 0 to 1 - the database doesn't
      // exist! Abort the transaction so that we don't create it here.
      openRequest.transaction!.abort();
      indexedDbExists = false;
    }.toJS;
    final database = await openRequest.complete<IDBDatabase>();

    indexedDbExists ??= true;
    database.close();
  } catch (_) {
    // May throw due to us aborting in the upgrade callback.
  }

  return indexedDbExists ?? false;
}

/// Deletes a database from IndexedDb if supported.
Future<void> deleteDatabaseInIndexedDb(String databaseName) async {
  final idb = globalContext['indexedDB'] as IDBFactory;
  await idb.deleteDatabase(databaseName).complete<JSAny?>();
}

/// Collects all drift OPFS databases.
Future<List<String>> opfsDatabases() async {
  final storage = storageManager;
  if (storage == null) return const [];

  var directory = await storage.directory;
  try {
    directory = await directory.getDirectory('drift_db');
  } on Object {
    // The drift_db folder doesn't exist, so there aren't any databases.
    return const [];
  }

  return [
    await for (final entry in directory.list())
      if (entry.isDirectory) entry.name,
  ];
}

/// Constructs the path used by drift to store a database in the origin-private
/// section of the agent's file system.
String pathForOpfs(String databaseName) {
  return 'drift_db/$databaseName';
}

/// Deletes the OPFS folder storing a database with the given [databaseName] if
/// such folder exists.
Future<void> deleteDatabaseInOpfs(String databaseName) async {
  final storage = storageManager;
  if (storage == null) return;

  var directory = await storage.directory;
  try {
    directory = await directory.getDirectory('drift_db');
    await directory.remove(databaseName, recursive: true);
  } on Object {
    // fine, an error probably means that the database didn't exist in the first
    // place.
  }
}

extension CompleteIdbRequest on IDBRequest {
  Future<T> complete<T extends JSAny?>() {
    final completer = Completer<T>.sync();

    EventStreamProviders.successEvent.forTarget(this).listen((event) {
      completer.complete(result as T);
    });
    EventStreamProviders.errorEvent.forTarget(this).listen((event) {
      completer.completeError(error ?? event);
    });

    return completer.future;
  }
}

extension CompleteOpenIdbRequest on IDBRequest {
  Future<T> completeOpen<T extends JSAny?>() {
    final completer = Completer<T>.sync();

    EventStreamProviders.successEvent.forTarget(this).listen((event) {
      completer.complete(result as T);
    });
    EventStreamProviders.errorEvent.forTarget(this).listen((event) {
      completer.completeError(error ?? event);
    });
    EventStreamProviders.blockedEvent.forTarget(this).listen((event) {
      completer.completeError(error ?? event);
    });

    return completer.future;
  }
}

# sqlite3.dart

This project contains Dart packages to use SQLite from Dart via `dart:ffi`.

The main package in this repository is [`sqlite3`](sqlite3), which contains all the Dart apis and their implementation.
`package:sqlite3` is a pure-Dart package without a dependency on Flutter. It can be used in Dart CLI applications or
servers.

The `sqlite3_flutter_libs` and `sqlcipher_flutter_libs` packages contain no Dart code at all. Flutter users can depend
on one of them to include native libraries in their apps.
# sqlite3.dart

This project contains Dart packages to use SQLite from Dart via `dart:ffi`.

The main package in this repository is [`sqlite3`](sqlite3), which contains all the Dart apis and their implementation.
`package:sqlite3` is a pure-Dart package without a dependency on Flutter.
It can be used both in Flutter apps or in standalone Dart applications.

The `sqlite3_flutter_libs` and `sqlcipher_flutter_libs` packages contain no Dart code at all. Flutter users can depend
on one of them to include native libraries in their apps.

`package:sqlite3_test` contains utilities that make integrating SQLite databases into Dart tests easier.
In particular, they patch `CURRENT_TIMESTAMP` and related constructs to return the (potentially faked) time
returned by `package:clock`.

## Example Usage

A file with basic usage examples for pure Dart can be found [here](sqlite3/example/main.dart).

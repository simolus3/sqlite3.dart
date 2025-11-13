# sqlite3.dart

This project contains Dart packages to use SQLite from Dart via `dart:ffi`.

The main package in this repository is [`sqlite3`](sqlite3), which contains all the Dart apis and their implementation.
`package:sqlite3` is a pure-Dart package without a dependency on Flutter.
It can be used both in Flutter apps or in standalone Dart applications.

`package:sqlite3_test` contains utilities that make integrating SQLite databases into Dart tests easier.
In particular, they patch `CURRENT_TIMESTAMP` and related constructs to return the (potentially faked) time
returned by `package:clock`.

`package:sqlite3_web` contains helpers for running SQLite on the web, including code to compile web workers
that help with the process.

## Example Usage

A file with basic usage examples for pure Dart can be found [here](sqlite3/example/main.dart).

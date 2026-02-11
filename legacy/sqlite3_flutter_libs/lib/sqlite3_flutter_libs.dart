/// This package does not do anything.
///
/// This package used to provide SQLite libraries for use with version 2.x of
/// the `sqlite3` package. Starting from version 3.x, this separate package is
/// no longer necessary.
///
/// Please see the [documentation on upgrading](https://github.com/simolus3/sqlite3.dart/blob/main/UPGRADING_TO_V3.md).
/// The reason for keeping this package around is that other packages can depend
/// on version `0.6.0` after upgrading to `package:sqlite3` version 3.x. This
/// ensures that the old Flutter build scripts are guaranteed to not be part of
/// the build.
library sqlite3_flutter_libs;

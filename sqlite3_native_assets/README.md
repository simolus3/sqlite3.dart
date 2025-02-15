__Like native assets, this package is experimental.__

This package provides SQLite as a [native code asset](https://dart.dev/interop/c-interop#native-assets).

It has the same functionality as the `sqlite3_flutter_libs` package,
except that it works without Flutter.

## Getting started

Add this package to your dependencies: `dart pub add sqlite3_native_assetes`.
That's it! No build scripts to worry about, it works out of the box.

## Usage

You can keep using all your existing code using `package:sqlite3`.
The only difference is how you access it.
For now, you'll have to replace the top-level `sqlite3` getter
with `sqlite3Native`.

```dart
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_native_assets/sqlite3_native_assets.dart';

void main() {
  final Sqlite3 sqlite3 = sqlite3Native;
  print('Using sqlite3 ${sqlite3.version}');
}
```

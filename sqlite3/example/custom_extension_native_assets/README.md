This shows how a custom SQLite extension can be linked with native assets.

The extension (https://github.com/asg017/sqlite-vec) is built with a code asset that will download
the extension as a prebuilt file from its GitHub releases.

SQLite extensions are shared libraries that have a function called `sqlite3_$extensionName_init`.
With the hook linking the extension, you can bind to that function with Dart:

```dart
@Native<Int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>()
external int sqlite3_vec_init(
  Pointer<Void> db,
  Pointer<Void> pzErrMsg,
  Pointer<Void> pApi,
);

```

This will then allow linking the extension:

```dart
extension LoadVectorExtension on Sqlite3 {
  void loadSqliteVectorExtension() {
    ensureExtensionLoaded(
      SqliteExtension(
        Native.addressOf<
          NativeFunction<
            Int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
          >
        >(sqlite3_vec_init).cast(),
      ),
    );
  }
}
```

To try this example, run `dart run example/main.dart`.

import 'dart:io';

/// Patches sqlite3mc to be easier to compile to WebAssembly without Emscripten.
///
/// sqlite3mc calls `snprintf` and `sprintf` directly in a few places. The
/// wasi-libc implementations of those go through `vfprintf`, which pulls in
/// stdio and with it the `fd_write` and `fd_close` WASI imports. We replace
/// these calls with `sqlite3_snprintf`. Note that `sqlite3_snprintf` swaps the
/// first two parameters, and returns a pointer to its buffer instead of the
/// number of characters written.
void main(List<String> args) {
  final file = File(args.single);
  var source = file.readAsStringSync();

  void replace(String from, String to) {
    final matches = from.allMatches(source).length;
    if (matches != 1) {
      throw StateError(
        'Expected exactly one occurrence of `$from` in ${file.path}, '
        'found $matches.',
      );
    }

    source = source.replaceFirst(from, to);
  }

  // hwcheck.c, the return value is used to compute the next offset.
  replace(
    '''
        int n = snprintf(hwInfoBuf + offset, sizeof(hwInfoBuf) - offset,
                         (offset == 0) ? "%s" : ",%s", featureTags[k].name);''',
    '''
        int n = (int) strlen(sqlite3_snprintf((int) (sizeof(hwInfoBuf) - offset), hwInfoBuf + offset,
                         (offset == 0) ? "%s" : ",%s", featureTags[k].name)); // patched by patch_sqlite3mc.dart''',
  );

  // argon2 encoding
  replace(
    'sprintf(tmp, "%lu", (unsigned long)(x));',
    'sqlite3_snprintf(sizeof(tmp), tmp, "%lu", (unsigned long)(x)); // patched by patch_sqlite3mc.dart',
  );

  // rekey_salt pragma
  replace(
    'sprintf(&saltHex[2*j], "%02x", saltRaw[j]);',
    'sqlite3_snprintf(3, &saltHex[2*j], "%02x", saltRaw[j]); // patched by patch_sqlite3mc.dart',
  );

  file.writeAsStringSync(source);
}

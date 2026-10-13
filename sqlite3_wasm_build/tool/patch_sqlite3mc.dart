import 'dart:io';

/// Patches sqlite3mc to be easier to compile to WebAssembly without Emscripten.
///
/// 1. Avoid `memset_explicit` call which is not available in wasi-libc.
/// 2. Avoid `__wasi_random_get` call by patching out `defined(__wasi__)`
///    blocks. That makes it use `getentropy`, which we patch in `getentropy.c`.
void main(List<String> args) {
  final file = File(args.single);
  final output = StringBuffer();

  var isInEntropyC = false;
  var isInIgnoredBlock = false;

  for (final line in file.readAsLinesSync()) {
    if (isInIgnoredBlock) {
      if (line.contains('#else') || line.contains('#elif')) {
        isInIgnoredBlock = false;
      } else {
        continue;
      }
    }

    if (line.contains('Begin of #include "csprng_entropy.c"')) {
      isInEntropyC = true;
    }
    if (line.contains('End of #include "csprng_entropy.c"')) {
      isInEntropyC = false;
    }

    if (isInEntropyC && line.contains('#elif defined(__wasi__)')) {
      isInIgnoredBlock = true;
      continue;
    }

    if (line.contains('memset_explicit')) {
      output.writeln(
        line.replaceFirst(
          'memset_explicit(v, 0, n);',
          'explicit_bzero(v, n); // patched by patch_sqlite3mc.dart',
        ),
      );

      continue;
    }

    output.writeln(line);
  }

  file.writeAsStringSync(output.toString());
}

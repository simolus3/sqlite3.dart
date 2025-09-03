import 'package:code_assets/code_assets.dart';
import 'package:sqlite3_native_assets/src/defines.dart';
import 'package:sqlite3_native_assets/src/source.dart';
import 'package:sqlite3_native_assets/src/user_defines.dart';
import 'package:test/test.dart';

void main() {
  group('parses sources', () {
    test('default', () {
      final source = SqliteSource.parse(UserDefinesOptions.fromMap({}));
      expect(source, isA<DownloadAmalgamation>());
    });

    test('explicit url', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {'amalgamation': 'https://example.org/sqlite.zip'},
        }),
      );
      expect(
        source,
        isA<DownloadAmalgamation>().having(
          (e) => e.uri,
          'uri',
          'https://example.org/sqlite.zip',
        ),
      );
    });

    test('explicit url, custom file', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {
            'amalgamation': {
              'uri': 'https://example.org/sqlite.zip',
              'filename': 'sqlite3mc.c',
            },
          },
        }),
      );
      expect(
        source,
        isA<DownloadAmalgamation>()
            .having((e) => e.uri, 'uri', 'https://example.org/sqlite.zip')
            .having((e) => e.filename, 'filename', 'sqlite3mc.c'),
      );
    });

    test('local source', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {'local': 'src/sqlite3.c'},
        }),
      );
      expect(
        source,
        isA<ExistingAmalgamation>().having(
          (e) => e.sqliteSource,
          'sqliteSource',
          'src/sqlite3.c',
        ),
      );
    });

    test('use from system', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {'system': null},
        }),
      );
      expect(source, isA<UseFromSystem>());
    });

    test('use from executable', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {'executable': null},
        }),
      );
      expect(source, isA<UseFromExecutable>());
    });

    test('use from process', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({
          'source': {'process': null},
        }),
      );
      expect(source, isA<UseFromProcess>());
    });

    test('dont build', () {
      final source = SqliteSource.parse(
        UserDefinesOptions.fromMap({'source': false}),
      );
      expect(source, isA<DontLinkSqlite>());
    });
  });

  group('parses compile-time options', () {
    test('default', () {
      final defines = CompilerDefines.parse(
        UserDefinesOptions.fromMap({}),
        OS.linux,
      );
      expect(defines, contains('SQLITE_OMIT_TRACE'));
    });

    test('with additional list', () {
      final defines = CompilerDefines.parse(
        UserDefinesOptions.fromMap({
          'defines': ['FOO', 'BAR=1'],
        }),
        OS.linux,
      );
      expect(defines, contains('FOO'));
      expect(defines, contains('BAR'));
    });

    test('includes SQLITE_API on Windows', () {
      final defines = CompilerDefines.parse(
        UserDefinesOptions.fromMap({
          'defines': ['FOO', 'BAR=1'],
        }),
        OS.windows,
      );
      expect(defines, containsPair('SQLITE_API', '__declspec(dllexport)'));
      expect(defines, contains('FOO'));
      expect(defines, contains('BAR'));
    });

    test('overriding defaults', () {
      final defines = CompilerDefines.parse(
        UserDefinesOptions.fromMap({
          'defines': {
            'defines': {'SQLITE_OMIT_TRACE': '0'},
          },
        }),
        OS.linux,
      );

      expect(defines, contains('SQLITE_ENABLE_MATH_FUNCTIONS'));
      expect(defines['SQLITE_OMIT_TRACE'], '0');
    });

    test('disabling defaults', () {
      final defines = CompilerDefines.parse(
        UserDefinesOptions.fromMap({
          'defines': {
            'default_options': false,
            'defines': {'SQLITE_OMIT_TRACE': '0'},
          },
        }),
        OS.linux,
      );

      expect(defines, {'SQLITE_OMIT_TRACE': '0'});
    });
  });
}

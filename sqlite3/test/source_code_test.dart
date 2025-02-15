@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('does not import legacy JS interop files', () {
    final failures = <(String, String)>[];

    void check(FileSystemEntity e) {
      switch (e) {
        case File():
          if (p.extension(e.path) != '.dart') return;

          final text = e.readAsStringSync();
          CompilationUnit parsed;
          try {
            parsed = parseString(content: text).unit;
          } catch (ex) {
            print('Could not parse ${e.path}');
            rethrow;
          }

          for (final directive in parsed.directives) {
            if (directive is ImportDirective) {
              final uri = directive.uri.stringValue!;
              if (uri.contains('package:js') ||
                  uri == 'dart:js' ||
                  uri == 'dart:js_util' ||
                  uri == 'dart:html' ||
                  uri == 'dart:indexeddb') {
                failures.add((e.path, directive.toString()));
              }
            }
          }

        case Directory():
          for (final entry in e.listSync()) {
            check(entry);
          }
      }
    }

    final root = Directory('lib/');
    check(root);

    expect(failures, isEmpty,
        reason: 'This package should not import legacy JS code.');
  });
}

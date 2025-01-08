@Tags(['ffi'])
library;

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:sqlite3/src/jsonb.dart';

void main() {
  group('encode', () {
    void expectEncoded(Object? object, String expectedHex) {
      final encoded = jsonb.encode(object);
      final hex =
          encoded.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, expectedHex);
    }

    test('null', () {
      expectEncoded(null, '00');
    });

    test('booleans', () {
      expectEncoded(true, '01');
      expectEncoded(false, '02');
    });

    test('integers', () {
      expectEncoded(0, '1330');
      expectEncoded(-1, '232d31');
    });

    test('doubles', () {
      expectEncoded(0.0, '35302e30');
      expectEncoded(-0.0, '452d302e30');
    });

    test('array', () {
      expectEncoded([], '0b');
      expectEncoded([true], 'fb000000000000000101');
    });

    test('object', () {
      expectEncoded({}, '0c');
      expectEncoded({'a': true}, 'fc0000000000000003186101');
    });
  });

  group('round trips', () {
    late Database database;
    late PreparedStatement jsonb2json;

    setUpAll(() {
      database = sqlite3.openInMemory();
      jsonb2json = database.prepare('SELECT json(?);');
    });

    tearDownAll(() => database.dispose());

    void check(Object? value, {String? expectDecodesAs}) {
      // Check our encoder -> sqlite3 decoder
      final sqliteDecoded = jsonb2json
          .select([jsonb.encode(value)])
          .single
          .values
          .single as String;
      if (expectDecodesAs != null) {
        expect(sqliteDecoded, expectDecodesAs);
      } else {
        expect(json.decode(sqliteDecoded), value);
      }
    }

    test('primitives', () {
      check(null);
      check(true);
      check(false);
      check(0);
      check(-1);
      check(0.0);
      check(double.infinity, expectDecodesAs: 'Infinity');
      check(double.negativeInfinity, expectDecodesAs: '-Infinity');
      check(double.nan, expectDecodesAs: 'NaN');
      check('hello world');
      check('hello " world');
      check('hello \n world');
    });

    test('arrays', () {
      check([]);
      check([1, 2, 3]);
      check([0, 1.1, 'hello', false, null, 'world']);
    });

    test('objects', () {
      check({});
      check({'foo': 'bar'});
      check({'a': null, 'b': true, 'c': 0, 'd': 0.1, 'e': 'hi'});
    });
  });
}

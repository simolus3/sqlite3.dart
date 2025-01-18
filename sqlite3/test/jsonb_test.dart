@Tags(['ffi'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  final supportsJsonb = sqlite3.version.versionNumber >= 3045000;

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
      expectEncoded({'a': true}, 'fc00000000000000031a6101');
    });

    test('does not encode circular elements', () {
      final selfContainingList = [];
      selfContainingList.add(selfContainingList);
      final selfContainingMap = {};
      selfContainingMap['.'] = selfContainingMap;

      expect(() => jsonb.encode(selfContainingList),
          throwsA(isA<JsonCyclicError>()));
      expect(() => jsonb.encode(selfContainingMap),
          throwsA(isA<JsonCyclicError>()));
    });

    test('does not encode invalid elements', () {
      expect(() => jsonb.encode(jsonb),
          throwsA(isA<JsonUnsupportedObjectError>()));
    });

    test('can call toJson', () {
      expectEncoded(_CustomJsonRepresentation(), '01');
    });
  });

  group('decode', () {
    Object? decode(String hex) {
      expect(hex.length.isEven, true);
      final bytes = Uint8List(hex.length ~/ 2);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = int.parse(hex.substring(i * 2, (i * 2) + 2), radix: 16);
      }
      return jsonb.decode(bytes);
    }

    void expectDecoded(String hex, Object? decoded) {
      expect(decode(hex), decoded);
    }

    test('null', () {
      expectDecoded('00', null);
    });

    test('true', () {
      expectDecoded('01', true);
    });

    test('false', () {
      expectDecoded('02', false);
    });

    test('integers', () {
      expectDecoded('1330', 0);
      expectDecoded('232d31', -1);
    });

    test('doubles', () {
      expectDecoded('35302e30', 0.0);
      expectDecoded('452d302e30', -0.0);
    });

    test('array', () {
      expectDecoded('0b', []);
      expectDecoded('1b01', [true]);
    });

    test('object', () {
      expectDecoded('0c', {});
      expectDecoded('3c1a6101', {'a': true});
    });

    test('supports long primitives', () {
      // "Future versions of SQLite might extend the JSONB format with elements
      // that have a zero element type but a non-zero size. In that way, legacy
      // versions of SQLite will interpret the element as a NULL for backwards
      // compatibility while newer versions will interpret the element in some
      // other way. "
      expectDecoded('30000000', null);
    });

    test('fails for invalid element types', () {
      expect(() => decode('0d'), throwsA(_isMalformedJsonException));
      expect(() => decode('0e'), throwsA(_isMalformedJsonException));
      expect(() => decode('0f'), throwsA(_isMalformedJsonException));
    });

    test('fails for trailing data', () {
      expect(() => decode('10'), throwsA(_isMalformedJsonException));
    });
  });

  group('round trips', () {
    late Database database;
    late PreparedStatement jsonb2json, json2jsonb;

    setUpAll(() {
      database = sqlite3.openInMemory();
      if (supportsJsonb) {
        jsonb2json = database.prepare('SELECT json(?);');
        json2jsonb = database.prepare('SELECT jsonb(?);');
      }
    });

    tearDownAll(() => database.dispose());

    void check(Object? value, {String? expectDecodesAs}) {
      final valueMatcher = switch (value) {
        double(isNaN: true) => isNaN,
        _ => equals(value),
      };

      // Check our encoder -> our decoder roundtrip
      expect(jsonb.decode(jsonb.encode(value)), valueMatcher);

      if (supportsJsonb) {
        // Check our encoder -> sqlite3 decoder rountrip
        final sqliteDecoded = jsonb2json
            .select([jsonb.encode(value)])
            .single
            .values
            .single as String;
        if (expectDecodesAs != null) {
          expect(sqliteDecoded, expectDecodesAs);
        } else {
          expect(json.decode(sqliteDecoded), valueMatcher);
        }

        // Check sqlite3 encoder -> our decoder roundtrip
        final sqliteEncoded = json2jsonb
            .select([jsonb.encode(value)])
            .single
            .values
            .single as Uint8List;
        expect(jsonb.decode(sqliteEncoded), valueMatcher);
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

    test(
      'did use sqlite3 decoder',
      () {},
      skip: supportsJsonb
          ? null
          : 'Roundtrip tests with SQLite were skipped because the available '
              'SQLite version does not support JSONB.',
    );
  });
}

final class _CustomJsonRepresentation {
  Object? toJson() => true;
}

final _isMalformedJsonException =
    isA<ArgumentError>().having((e) => e.message, 'message', 'Malformed JSONB');

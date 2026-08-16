@TestOn('browser')
@Tags(['wasm'])
library;

import 'package:sqlite3/src/wasm/js_interop.dart';
import 'package:sqlite3/src/wasm/vfs/async_opfs/sync_channel.dart';
import 'package:test/test.dart';

void main() {
  group('OPFS message serializer', () {
    late MessageSerializer serializer;

    setUp(() {
      serializer = MessageSerializer(
        SharedArrayBuffer(MessageSerializer.totalSize),
      );
    });

    test('round-trips file offsets and sizes beyond 2 GiB', () {
      const values = [
        -1,
        0,
        0x7fffffff,
        0x80000000,
        0x100000000,
        // SQLite's maximum page count with its maximum 64 KiB page size.
        0xffff_fffe_0000,
      ];

      for (final value in values) {
        serializer.write(Flags(value, value, value));
        final decoded = MessageSerializer.readFlags(serializer);

        expect(decoded.flag0, value);
        expect(decoded.flag1, value);
        expect(decoded.flag2, value);
      }
    });

    test('keeps filename metadata separate from 64-bit flags', () {
      serializer.write(
        NameAndInt32Flags('/nested/database.sqlite', 0x80000000, -1, 42),
      );

      final decoded = MessageSerializer.readNameAndFlags(serializer);
      expect(decoded.name, '/nested/database.sqlite');
      expect(decoded.flag0, 0x80000000);
      expect(decoded.flag1, -1);
      expect(decoded.flag2, 42);
    });
  });
}

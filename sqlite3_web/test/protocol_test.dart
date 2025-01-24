@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3_web/src/channel.dart';
import 'package:sqlite3_web/src/protocol.dart';
import 'package:test/test.dart';

void main() {
  late TestServer server;
  late TestClient client;

  setUp(() async {
    final (endpoint, channel) = await createChannel();

    server = TestServer(channel);
    client = TestClient(endpoint.connect());
  });

  tearDown(() async {
    await server.close();
    await client.close();
  });

  group('TypeCode', () {
    test('is compatible with dartify()', () {
      for (final value in [
        1,
        3.4,
        true,
        null,
        {'custom': 'object'},
        'string',
        Uint8List(10),
      ]) {
        final (_, jsified) = TypeCode.encodeValue(value);
        expect(jsified.dartify(), value);
      }
    });
  });

  test('serializes types in request', () async {
    server.handleRequestFunction = expectAsync1((request) async {
      final run = request as RunQuery;
      expect(run.sql, 'sql');
      expect(run.parameters, [
        1,
        1.0,
        true,
        false,
        'a string',
        isA<Uint8List>().having((e) => e.length, 'length', 10),
        isDart2Wasm ? 100 : BigInt.from(100),
        null,
        {'custom': 'object'},
      ]);
      if (isDart2Wasm) {
        // Make sure we don't loose type information in the js conversion across
        // the message ports.
        expect(run.parameters[0].runtimeType, int);
        expect(run.parameters[1].runtimeType, double);
      }

      return SimpleSuccessResponse(
        requestId: request.requestId,
        response: null,
      );
    });

    await client.sendRequest(
      RunQuery(
        requestId: 0,
        databaseId: 0,
        sql: 'sql',
        parameters: [
          1,
          1.0,
          true,
          false,
          'a string',
          Uint8List(10),
          BigInt.from(100),
          null,
          {'custom': 'object'},
        ],
        returnRows: true,
      ),
      MessageType.simpleSuccessResponse,
    );
  });

  test('serializes types in response', () async {
    server.handleRequestFunction = expectAsync1((request) async {
      return RowsResponse(
        requestId: request.requestId,
        resultSet: ResultSet(
          ['a'],
          null,
          [
            [1],
            [Uint8List(10)],
            [null],
            ['string value'],
          ],
        ),
      );
    });

    final response = await client.sendRequest(
      RunQuery(
        requestId: 0,
        databaseId: 0,
        sql: 'sql',
        parameters: [],
        returnRows: true,
      ),
      MessageType.rowsResponse,
    );
    final resultSet = response.resultSet;

    expect(resultSet.length, 4);
    expect(
      resultSet.map((e) => e['a']),
      [1, Uint8List(10), null, 'string value'],
    );
  });
}

const isDart2Wasm = bool.fromEnvironment('dart.tool.dart2wasm');

final class TestServer extends ProtocolChannel {
  final StreamController<Notification> _notifications = StreamController();
  Future<Response> Function(Request request) handleRequestFunction =
      (req) async {
    throw 'unsupported';
  };

  TestServer(super.channel);

  Stream<Notification> get notification => _notifications.stream;

  @override
  void handleNotification(Notification notification) {
    _notifications.add(notification);
  }

  @override
  Future<Response> handleRequest(Request request) {
    return handleRequestFunction(request);
  }
}

final class TestClient extends ProtocolChannel {
  TestClient(super.channel);

  @override
  void handleNotification(Notification notification) {}

  @override
  Future<Response> handleRequest(Request request) {
    throw UnimplementedError();
  }
}

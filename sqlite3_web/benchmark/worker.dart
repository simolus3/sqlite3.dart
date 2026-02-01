import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/locks.dart';
import 'package:web/web.dart';

import '../example/controller.dart';
import 'message.dart';

final _locks = WebLocks.instance!;

void main() {
  WorkerEnvironment environment;

  if (globalContext.instanceOfString('SharedWorkerGlobalScope')) {
    // This shared worker is used both to hand out database access and to
    // coordinate multiple tabs running concurrency benchmarks. We encapsulate
    // messages from the sqlite3_async package in a WorkerMessage struct, which
    // allows this worker to speak both protocols.
    final fakeEnvironment = environment = FakeWorkerEnvironment(
      WorkerConnector.defaultWorkers(Uri.base),
    );

    final scope = globalContext as SharedWorkerGlobalScope;
    final clients = ClientsDriver();
    clients.run();

    EventStreamProviders.connectEvent.forTarget(scope).listen((event) {
      for (final port in (event as MessageEvent).ports.toDart) {
        port.start();

        EventStreamProviders.messageEvent.forTarget(port).listen((message) {
          final data = message.data as WorkerMessage;
          switch (ToWorkerMessageType.values.byName(data.type)) {
            case ToWorkerMessageType.sqlite:
              fakeEnvironment.postMessage(data.payload);
            case ToWorkerMessageType.connectTab:
              final payload = data.payload as ConnectTab;
              clients._events.add(
                _ClientConnected(ConnectedClient(port), payload.lockName),
              );
          }
        });
      }
    });
  } else {
    environment = WorkerEnvironment();
  }

  WebSqlite.workerEntrypoint(
    controller: ExampleController(),
    environment: environment,
  );
}

/// Actor handling tabs connecting, disconnecting and requesting benchmark runs.
final class ClientsDriver {
  final StreamController<_ClientsDriverEvent> _events = StreamController();
  final List<ConnectedClient> _clients = [];

  void run() async {
    await for (final event in _events.stream) {
      _handleEvent(event);
    }
  }

  void _handleEvent(_ClientsDriverEvent event) {
    switch (event) {
      case _ClientConnected():
        _clients.add(event.client);
        _reindexClients();

        _locks.request(event.lockName).then((lock) {
          _events.add(_ClientDisconnected(event.client));
          lock.release();
        });
      case _ClientDisconnected():
        _clients.remove(event.client);
        _reindexClients();
    }
  }

  void _reindexClients() {
    for (final (i, client) in _clients.indexed) {
      client.port.postMessage(
        WorkerMessage(
          type: ToClientMessageType.tabId.name,
          payload: ReceiveTabId(index: i.toJS, numTabs: _clients.length.toJS),
        ),
      );
    }
  }
}

final class ConnectedClient {
  final MessagePort port;

  ConnectedClient(this.port);
}

sealed class _ClientsDriverEvent {}

final class _ClientConnected implements _ClientsDriverEvent {
  final ConnectedClient client;
  final String lockName;

  _ClientConnected(this.client, this.lockName);
}

final class _ClientDisconnected implements _ClientsDriverEvent {
  final ConnectedClient client;

  _ClientDisconnected(this.client);
}

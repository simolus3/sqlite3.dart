/// @docImport 'database.dart';
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

/// Environment for workers hosting SQLite databases.

abstract interface class WorkerEnvironment {
  /// A connector that can be used to spawn nested workers, if that feature is
  /// available in the current context.
  WorkerConnector get connector;

  /// Incoming messages.
  ///
  /// For dedicated workers, this would be all messages received on the
  /// [DedicatedWorkerGlobalScope]. For shared workers, all messages received on
  /// connecting ports.
  Stream<MessageEvent> get incomingMessages;

  /// The default environment for the current worker context.
  ///
  /// This should only be called in Dart programs compiled to workers.
  factory WorkerEnvironment() {
    final context = globalContext;
    if (context.instanceOfString('DedicatedWorkerGlobalScope')) {
      return _DedicatedWorkerEnvironment();
    } else {
      return _SharedWorkerEnvironment();
    }
  }
}

abstract class _WorkerEnvironment<T extends WorkerGlobalScope>
    implements WorkerEnvironment {
  final T scope;

  @override
  final WorkerConnector connector = WorkerConnector.defaultWorkers(Uri.base);

  _WorkerEnvironment() : scope = globalContext as T;
}

final class _DedicatedWorkerEnvironment
    extends _WorkerEnvironment<DedicatedWorkerGlobalScope> {
  @override
  Stream<MessageEvent> get incomingMessages {
    return EventStreamProviders.messageEvent.forTarget(scope);
  }
}

final class _SharedWorkerEnvironment
    extends _WorkerEnvironment<SharedWorkerGlobalScope> {
  @override
  Stream<MessageEvent> get incomingMessages {
    // Listen for connect events, then watch each connected port to send a a
    // connect message.
    // Tabs will only use one message port to this worker, but may use multiple
    // connections for different databases. So we're not using the connect port
    // for the actual connection and instead wait for clients to send message
    // ports through the connect port.
    return Stream.multi((listener) {
      final connectPorts = <MessagePort>[];
      final subscriptions = <StreamSubscription>[];

      void handlePort(MessagePort port) {
        connectPorts.add(port);
        port.start();

        subscriptions.add(
          EventStreamProviders.messageEvent.forTarget(port).listen((event) {
            listener.addSync(event);
          }),
        );
      }

      subscriptions.add(
        EventStreamProviders.connectEvent.forTarget(scope).listen((event) {
          for (final port in (event as MessageEvent).ports.toDart) {
            handlePort(port);
          }
        }),
      );

      listener.onCancel = () {
        for (final subscription in subscriptions) {
          subscription.cancel();
        }
      };
    });
  }
}

/// A worker environment that isn't in an actual web worker.
///
/// This package uses this to connect to a local worker implementation running
/// in the same context if workers aren't available.
final class FakeWorkerEnvironment implements WorkerEnvironment, WorkerHandle {
  @override
  final WorkerConnector connector;

  @override
  final EventTarget targetForErrorEvents = EventTarget();

  final StreamController<MessageEvent> _messages = StreamController();

  FakeWorkerEnvironment([this.connector = const WorkerConnector.unsupported()]);

  @override
  Stream<MessageEvent> get incomingMessages {
    return _messages.stream;
  }

  /// Adds a message that will show up in [incomingMessages].
  @override
  void postMessage(JSAny? message, [JSObject? options]) {
    _messages.add(MessageEvent('message', MessageEventInit(data: message)));
  }

  void close() {
    _messages.close();
  }
}

/// An interface abstracting over `Worker` and `SharedWorker` constructors,
/// allowing clients of `sqlite3_web` to customize if and how workers are used.
abstract interface class WorkerConnector {
  /// Spawn a new shared database worker, or returns `null` if dedicated workers
  /// aren't supported.
  WorkerHandle? spawnDedicatedWorker();

  /// Spawn a new shared database worker, or returns `null` if shared workers
  /// aren't supported.
  WorkerHandle? spawnSharedWorker();

  /// The default implementation, spawning workers with the [Worker] and
  /// [SharedWorker] constructors.
  ///
  /// The [uri] must point to a compiled Dart program using
  /// [WebSqlite.workerEntrypoint] to receive messages.
  factory WorkerConnector.defaultWorkers(Uri uri) {
    return _DefaultWorkerConnector(uri);
  }

  /// A [WorkerConnector] implementation that doesn't allow the use of workers.
  const factory WorkerConnector.unsupported() = _WithoutWorkers;
}

/// Handle to a shared or dedicated web worker.
abstract interface class WorkerHandle {
  /// The web [EventTarget] representing the worker.
  ///
  /// This package will listen for errors on this target. Errors are assumed to
  /// be fatal and unhandled errors from the worker and will lead to the
  /// connection closing.
  EventTarget get targetForErrorEvents;

  /// Posts a JavaScript value as a message to this worker (or, for shared
  /// workers, the respective port).
  ///
  /// This method can wrap the message to send in another structure, allowing a
  /// single worker file to handle both `sqlite3_web` and other tasks.
  void postMessage(JSAny? msg, JSObject transfer);
}

final class _DefaultWorkerConnector implements WorkerConnector {
  final Uri _worker;

  _DefaultWorkerConnector(this._worker);

  @override
  WorkerHandle? spawnDedicatedWorker() {
    if (!globalContext.has('Worker')) {
      return null;
    }

    return _DedicatedWorker(
      Worker(_worker.toString().toJS, WorkerOptions(name: 'sqlite3_worker')),
    );
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    if (!globalContext.has('SharedWorker')) {
      return null;
    }

    final worker = SharedWorker(_worker.toString().toJS);
    worker.port.start();
    return _SharedWorker(worker);
  }
}

final class _WithoutWorkers implements WorkerConnector {
  const _WithoutWorkers();

  @override
  WorkerHandle? spawnDedicatedWorker() {
    return null;
  }

  @override
  WorkerHandle? spawnSharedWorker() {
    return null;
  }
}

final class _DedicatedWorker implements WorkerHandle {
  final Worker _worker;

  _DedicatedWorker(this._worker);

  @override
  void postMessage(JSAny? msg, JSObject transfer) {
    _worker.postMessage(msg, transfer);
  }

  @override
  EventTarget get targetForErrorEvents => _worker;
}

final class _SharedWorker implements WorkerHandle {
  final SharedWorker _worker;

  _SharedWorker(this._worker);

  @override
  void postMessage(JSAny? msg, JSObject transfer) {
    _worker.port.postMessage(msg, transfer);
  }

  @override
  EventTarget get targetForErrorEvents => _worker;
}

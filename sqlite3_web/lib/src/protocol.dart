import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite3/common.dart';
import 'package:web/web.dart';

import 'api.dart';

/// Signature of a function allowing structured data to be sent between JS
/// contexts.
///
/// This is implemented by [WorkerExtension.postMessage],
/// [MessagePortExtension.postMessage] and
/// [DedicatedWorkerGlobalScopeExtension.postMessage].
typedef PostMessage = void Function(JSAny? msg, JSObject transfer);

enum MessageType<T extends Message> {
  custom<CustomRequest>(),
  open<OpenRequest>(),
  runQuery<RunQuery>(),
  fileSystemExists<FileSystemExistsQuery>(),
  fileSystemAccess<FileSystemAccess>(),
  simpleSuccessResponse<SimpleSuccessResponse>(),
  rowsResponse<RowsResponse>(),
  errorResponse<ErrorResponse>();

  static final Map<String, MessageType> byName = values.asNameMap();
}

/// Field names used when serializing messages to JS objects.
///
/// Since we're using unsafe JS interop here, these can't be mangled by dart2js.
/// Thus, we should keep them short.
class _UniqueFieldNames {
  static const buffer = 'b';
  static const columnNames = 'c';
  static const databaseId = 'd';
  static const databaseName = 'd'; // no clash, used on different types
  static const errorMessage = 'e';
  static const fileType = 'f';
  static const id = 'i';
  static const tableNames = 'n';
  static const parameters = 'p';
  static const storageMode = 's';
  static const sql = 's'; // not used in same message
  static const type = 't';
  static const wasmUri = 'u';
  static const responseData = 'r';
  static const returnRows = 'r';
  static const rows = 'r'; // no clash, used on different message types
}

sealed class Message {
  MessageType get type;

  static Message deserialize(JSObject object) {
    final type = MessageType
        .byName[(object[_UniqueFieldNames.type] as JSString).toDart]!;

    return switch (type) {
      MessageType.custom => CustomRequest.deserialize(object),
      MessageType.open => OpenRequest.deserialize(object),
      MessageType.runQuery => RunQuery.deserialize(object),
      MessageType.fileSystemExists => FileSystemExistsQuery.deserialize(object),
      MessageType.fileSystemAccess => FileSystemAccess.deserialize(object),
      MessageType.simpleSuccessResponse =>
        SimpleSuccessResponse.deserialize(object),
      MessageType.rowsResponse => RowsResponse.deserialize(object),
      MessageType.errorResponse => ErrorResponse.deserialize(object),
    };
  }

  void serialize(JSObject object, List<JSObject> transferred) {
    object[_UniqueFieldNames.type] = type.name.toJS;
  }

  void sendTo(PostMessage sender) {
    final serialized = JSObject();
    final transfer = <JSObject>[];
    serialize(serialized, transfer);

    sender(serialized, transfer.toJS);
  }

  void sendToWorker(Worker worker) {
    sendTo((msg, transfer) => worker.postMessage(msg, transfer));
  }

  void sendToPort(MessagePort port) {
    sendTo((msg, transfer) => port.postMessage(msg, transfer));
  }

  void sendToClient(DedicatedWorkerGlobalScope worker) {
    sendTo((msg, transfer) => worker.postMessage(msg, transfer));
  }
}

sealed class Request extends Message {
  /// A unique id, incremented by each endpoint when making requests over the
  /// channel.
  int requestId;
  final int? databaseId;

  Request({required this.requestId, this.databaseId});

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.id] = requestId.toJS;

    if (databaseId case final id?) {
      object[_UniqueFieldNames.databaseId] = id.toJS;
    }
  }

  Future<Response> tryRespond(FutureOr<Response> Function() function) async {
    try {
      return await function();
    } catch (e) {
      return ErrorResponse(message: e.toString(), requestId: requestId);
    }
  }
}

sealed class Response extends Message {
  /// The [Request.requestId] that this is a response of.
  final int requestId;

  Response({required this.requestId});

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.id] = requestId.toJS;
  }

  RemoteException interpretAsError() {
    return RemoteException(message: 'Did not respond with expected type');
  }
}

final class OpenRequest extends Request {
  final Uri wasmUri;

  final String databaseName;
  final StorageMode storageMode;

  OpenRequest({
    required super.requestId,
    required this.wasmUri,
    required this.databaseName,
    required this.storageMode,
  });

  factory OpenRequest.deserialize(JSObject object) {
    return OpenRequest(
      storageMode: StorageMode.values[
          (object[_UniqueFieldNames.storageMode] as JSNumber).toDartInt],
      databaseName: (object[_UniqueFieldNames.databaseName] as JSString).toDart,
      wasmUri:
          Uri.parse((object[_UniqueFieldNames.wasmUri] as JSString).toDart),
      requestId: object.requestId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.open;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.databaseName] = databaseName.toJS;
    object[_UniqueFieldNames.storageMode] = storageMode.index.toJS;
    object[_UniqueFieldNames.wasmUri] = wasmUri.toString().toJS;
  }
}

/// Allows users of this package to implement their own RPC calls handled by
/// workers hosting the database.
final class CustomRequest extends Request {
  final JSAny? payload;

  CustomRequest({
    required super.requestId,
    required this.payload,
    super.databaseId,
  });

  factory CustomRequest.deserialize(JSObject object) {
    return CustomRequest(
      requestId: object.requestId,
      payload: object[_UniqueFieldNames.responseData],
      databaseId: object.hasProperty(_UniqueFieldNames.databaseId.toJS).toDart
          ? object.databaseId
          : null,
    );
  }

  @override
  MessageType<Message> get type => MessageType.custom;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.responseData] = payload;
  }
}

/// The other side will respond with a [SimpleSuccessResponse] containing a
/// boolean indicating whether the file exists.
final class FileSystemExistsQuery extends Request {
  final FileType fsType;

  @override
  MessageType<Message> get type => MessageType.fileSystemExists;

  FileSystemExistsQuery({
    required this.fsType,
    required super.databaseId,
    required super.requestId,
  });

  factory FileSystemExistsQuery.deserialize(JSObject object) {
    return FileSystemExistsQuery(
      fsType: FileType
          .values[(object[_UniqueFieldNames.fileType] as JSNumber).toDartInt],
      databaseId: object.databaseId,
      requestId: object.requestId,
    );
  }

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.fileType] = fsType.index.toJS;
  }
}

/// Read or write to files of an opened database.
///
/// For reads, other side will respond with a [SimpleSuccessResponse] containing
/// the transferred buffer, which is cheap in JS because it gets moved.
/// For writes, the other side will respond with a [SimpleSuccessResponse]
/// not containing any value.
final class FileSystemAccess extends Request {
  /// For writes, the contents to write into the file. `null` for reads.
  final JSArrayBuffer? buffer;
  final FileType fsType;

  @override
  MessageType<Message> get type => MessageType.fileSystemAccess;

  FileSystemAccess({
    required super.databaseId,
    required super.requestId,
    required this.buffer,
    required this.fsType,
  });

  factory FileSystemAccess.deserialize(JSObject object) {
    return FileSystemAccess(
      databaseId: object.databaseId,
      requestId: object.requestId,
      buffer: object[_UniqueFieldNames.buffer] as JSArrayBuffer?,
      fsType: FileType
          .values[(object[_UniqueFieldNames.fileType] as JSNumber).toDartInt],
    );
  }

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.buffer] = buffer;
    object[_UniqueFieldNames.fileType] = fsType.index.toJS;

    if (buffer case var buffer?) {
      transferred.add(buffer);
    }
  }
}

final class RunQuery extends Request {
  final String sql;
  final List<Object?> parameters;
  final bool returnRows;

  RunQuery({
    required super.requestId,
    required int super.databaseId,
    required this.sql,
    required this.parameters,
    required this.returnRows,
  });

  factory RunQuery.deserialize(JSObject object) {
    return RunQuery(
      requestId: object.requestId,
      databaseId: object.databaseId,
      sql: (object[_UniqueFieldNames.sql] as JSString).toDart,
      parameters: [
        for (final raw
            in (object[_UniqueFieldNames.parameters] as JSArray).toDart)
          raw.dartify()
      ],
      returnRows: (object[_UniqueFieldNames.returnRows] as JSBoolean).toDart,
    );
  }

  @override
  MessageType<Message> get type => MessageType.runQuery;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.sql] = sql.toJS;
    object[_UniqueFieldNames.parameters] =
        <JSAny?>[for (final parameter in parameters) parameter.jsify()].toJS;
    object[_UniqueFieldNames.returnRows] = returnRows.toJS;
  }
}

final class SimpleSuccessResponse extends Response {
  final JSAny? response;

  SimpleSuccessResponse({required this.response, required super.requestId});

  factory SimpleSuccessResponse.deserialize(JSObject object) {
    return SimpleSuccessResponse(
      response: object[_UniqueFieldNames.responseData],
      requestId: object.requestId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.simpleSuccessResponse;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.responseData] = response;
  }
}

final class RowsResponse extends Response {
  final ResultSet resultSet;

  RowsResponse({required this.resultSet, required super.requestId});

  factory RowsResponse.deserialize(JSObject object) {
    final columnNames = [
      for (final entry
          in (object[_UniqueFieldNames.columnNames] as JSArray).toDart)
        (entry as JSString).toDart
    ];
    final rawTableNames = object[_UniqueFieldNames.tableNames];
    final tableNames = rawTableNames != null
        ? [
            for (final entry in (rawTableNames as JSArray).toDart)
              (entry as JSString).toDart
          ]
        : null;

    final rows = <List<Object?>>[];
    for (final row in (object[_UniqueFieldNames.rows] as JSArray).toDart) {
      final dartRow = <Object?>[];

      for (final column in (row as JSArray).toDart) {
        dartRow.add(column.dartify());
      }

      rows.add(dartRow);
    }

    return RowsResponse(
      resultSet: ResultSet(columnNames, tableNames, rows),
      requestId: object.requestId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.rowsResponse;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.rows] = <JSArray>[
      for (final row in resultSet.rows)
        <JSAny?>[
          for (final column in row) column.jsify(),
        ].toJS,
    ].toJS;

    object[_UniqueFieldNames.columnNames] = <JSString>[
      for (final entry in resultSet.columnNames) entry.toJS,
    ].toJS;

    if (resultSet.tableNames case var tableNames?) {
      object[_UniqueFieldNames.tableNames] = <JSString?>[
        for (final entry in tableNames) entry?.toJS,
      ].toJS;
    } else {
      object[_UniqueFieldNames.tableNames] = null;
    }
  }
}

final class ErrorResponse extends Response {
  final String message;

  ErrorResponse({required this.message, required super.requestId});

  factory ErrorResponse.deserialize(JSObject object) {
    return ErrorResponse(
      message: (object[_UniqueFieldNames.errorMessage] as JSString).toDart,
      requestId: object.requestId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.errorResponse;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.errorMessage] = message.toJS;
  }

  @override
  RemoteException interpretAsError() {
    return RemoteException(message: message);
  }
}

extension on JSObject {
  int get requestId {
    return (this[_UniqueFieldNames.id] as JSNumber).toDartInt;
  }

  int get databaseId {
    return (this[_UniqueFieldNames.databaseId] as JSNumber).toDartInt;
  }
}

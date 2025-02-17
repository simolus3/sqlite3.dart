import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart' as wasm_vfs;
// ignore: implementation_imports
import 'package:sqlite3/src/wasm/js_interop/core.dart';
import 'package:web/web.dart';

import 'types.dart';
import 'channel.dart';

/// Signature of a function allowing structured data to be sent between JS
/// contexts.
typedef PostMessage = void Function(JSAny? msg, JSObject transfer);

enum MessageType<T extends Message> {
  dedicatedCompatibilityCheck<CompatibilityCheck>(),
  sharedCompatibilityCheck<CompatibilityCheck>(),
  dedicatedInSharedCompatibilityCheck<CompatibilityCheck>(),
  custom<CustomRequest>(),
  open<OpenRequest>(),
  runQuery<RunQuery>(),
  fileSystemExists<FileSystemExistsQuery>(),
  fileSystemAccess<FileSystemAccess>(),
  fileSystemFlush<FileSystemFlushRequest>(),
  connect<ConnectRequest>(),
  startFileSystemServer<StartFileSystemServer>(),
  updateRequest<StreamRequest>(),
  rollbackRequest<StreamRequest>(),
  commitRequest<StreamRequest>(),
  simpleSuccessResponse<SimpleSuccessResponse>(),
  rowsResponse<RowsResponse>(),
  errorResponse<ErrorResponse>(),
  endpointResponse<EndpointResponse>(),
  closeDatabase<CloseDatabase>(),
  openAdditionalConnection<OpenAdditonalConnection>(),
  notifyUpdate<UpdateNotification>(),
  notifyRollback<EmptyNotification>(),
  notifyCommit<EmptyNotification>(),
  ;

  static final Map<String, MessageType> byName = values.asNameMap();
}

/// Field names used when serializing messages to JS objects.
///
/// Since we're using unsafe JS interop here, these can't be mangled by dart2js.
/// Thus, we should keep them short.
class _UniqueFieldNames {
  static const action = 'a'; // Only used in StreamRequest
  static const additionalData = 'a'; // only used in OpenRequest
  static const buffer = 'b';
  static const columnNames = 'c';
  static const databaseId = 'd';
  static const databaseName = 'd'; // no clash, used on different types
  static const errorMessage = 'e';
  static const fileType = 'f';
  static const id = 'i';
  static const updateKind = 'k';
  static const tableNames = 'n';
  static const onlyOpenVfs = 'o';
  static const parameters = 'p';
  static const storageMode = 's';
  static const serializedExceptionType = 's';
  static const sql = 's'; // not used in same message
  static const type = 't';
  static const wasmUri = 'u';
  static const updateTableName = 'u';
  static const responseData = 'r';
  static const returnRows = 'r';
  static const updateRowId = 'r';
  static const serializedException = 'r';
  static const rows = 'r'; // no clash, used on different message types
  static const typeVector = 'v';
}

sealed class Message {
  MessageType get type;

  static Message deserialize(JSObject object) {
    final type = MessageType
        .byName[(object[_UniqueFieldNames.type] as JSString).toDart]!;

    return switch (type) {
      MessageType.dedicatedCompatibilityCheck => CompatibilityCheck.deserialize(
          MessageType.dedicatedCompatibilityCheck, object),
      MessageType.sharedCompatibilityCheck => CompatibilityCheck.deserialize(
          MessageType.sharedCompatibilityCheck, object),
      MessageType.dedicatedInSharedCompatibilityCheck =>
        CompatibilityCheck.deserialize(
            MessageType.dedicatedInSharedCompatibilityCheck, object),
      MessageType.custom => CustomRequest.deserialize(object),
      MessageType.open => OpenRequest.deserialize(object),
      MessageType.startFileSystemServer =>
        StartFileSystemServer.deserialize(object),
      MessageType.runQuery => RunQuery.deserialize(object),
      MessageType.fileSystemExists => FileSystemExistsQuery.deserialize(object),
      MessageType.fileSystemAccess => FileSystemAccess.deserialize(object),
      MessageType.fileSystemFlush => FileSystemFlushRequest.deserialize(object),
      MessageType.connect => ConnectRequest.deserialize(object),
      MessageType.closeDatabase => CloseDatabase.deserialize(object),
      MessageType.openAdditionalConnection =>
        OpenAdditonalConnection.deserialize(object),
      MessageType.updateRequest ||
      MessageType.rollbackRequest ||
      MessageType.commitRequest =>
        StreamRequest.deserialize(type, object),
      MessageType.simpleSuccessResponse =>
        SimpleSuccessResponse.deserialize(object),
      MessageType.endpointResponse => EndpointResponse.deserialize(object),
      MessageType.rowsResponse => RowsResponse.deserialize(object),
      MessageType.errorResponse => ErrorResponse.deserialize(object),
      MessageType.notifyUpdate => UpdateNotification.deserialize(object),
      MessageType.notifyRollback ||
      MessageType.notifyCommit =>
        EmptyNotification.deserialize(type, object),
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

sealed class Notification extends Message {}

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

enum FileSystemImplementation {
  opfsShared('s'),
  opfsLocks('l'),
  indexedDb('i'),
  inMemory('m');

  final String jsRepresentation;

  const FileSystemImplementation(this.jsRepresentation);

  JSString get toJS => jsRepresentation.toJS;

  static FileSystemImplementation fromJS(JSString js) {
    final toDart = js.toDart;

    for (final entry in values) {
      if (entry.jsRepresentation == toDart) return entry;
    }

    throw ArgumentError('Unknown FS implementation: $toDart');
  }
}

final class OpenRequest extends Request {
  final Uri wasmUri;

  final String databaseName;
  final FileSystemImplementation storageMode;
  final bool onlyOpenVfs;

  /// Additional data passsed to `DatabaseController.openDatabase`.
  final JSAny? additionalData;

  OpenRequest({
    required super.requestId,
    required this.wasmUri,
    required this.databaseName,
    required this.storageMode,
    required this.onlyOpenVfs,
    this.additionalData,
  });

  factory OpenRequest.deserialize(JSObject object) {
    return OpenRequest(
      storageMode: FileSystemImplementation.fromJS(
          object[_UniqueFieldNames.storageMode] as JSString),
      databaseName: (object[_UniqueFieldNames.databaseName] as JSString).toDart,
      wasmUri:
          Uri.parse((object[_UniqueFieldNames.wasmUri] as JSString).toDart),
      requestId: object.requestId,
      // The onlyOpenVfs and transformedVfsName fields were not set in earlier
      // clients.
      onlyOpenVfs:
          (object[_UniqueFieldNames.onlyOpenVfs] as JSBoolean?)?.toDart == true,
      additionalData: object[_UniqueFieldNames.additionalData],
    );
  }

  @override
  MessageType<Message> get type => MessageType.open;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.databaseName] = databaseName.toJS;
    object[_UniqueFieldNames.storageMode] = storageMode.toJS;
    object[_UniqueFieldNames.wasmUri] = wasmUri.toString().toJS;
    object[_UniqueFieldNames.onlyOpenVfs] = onlyOpenVfs.toJS;
    object[_UniqueFieldNames.additionalData] = additionalData;
  }
}

/// Requests the receiving end of this message to connect to the channel
/// reachable through [endpoint].
///
/// This message it sent to dedicated and shared workers under their top-level
/// receive handler.
/// This can also be a request as part of an existing communication channel. In
/// that form, the client asks the receiver to forward the connect request to
/// a nested context. In particular, this is used for different tabs to connect
/// to a dedicated worker spawned by a shared worker.
/// As only dedicated workers can use synchronous file system APIs, this allows
/// different tabs to share a dedicated worker hosting a database with OPFS,
/// which is by far the most efficient way access dabases.
final class ConnectRequest extends Request {
  /// The endpoint under which the client is reachable.
  final WebEndpoint endpoint;

  ConnectRequest({required super.requestId, required this.endpoint});

  factory ConnectRequest.deserialize(JSObject object) {
    return ConnectRequest(
      requestId: object.requestId,
      endpoint: object[_UniqueFieldNames.responseData] as WebEndpoint,
    );
  }

  @override
  MessageType<Message> get type => MessageType.connect;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.responseData] = endpoint;
    transferred.add(endpoint.port);
  }
}

final class StartFileSystemServer extends Message {
  final wasm_vfs.WorkerOptions options;

  StartFileSystemServer({required this.options});

  factory StartFileSystemServer.deserialize(JSObject object) {
    return StartFileSystemServer(
        options:
            object[_UniqueFieldNames.responseData] as wasm_vfs.WorkerOptions);
  }

  @override
  MessageType<Message> get type => MessageType.startFileSystemServer;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.responseData] = options;
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

/// Requests the worker to flush the file system for a database.
final class FileSystemFlushRequest extends Request {
  @override
  MessageType<Message> get type => MessageType.fileSystemFlush;

  FileSystemFlushRequest({
    required super.databaseId,
    required super.requestId,
  });

  factory FileSystemFlushRequest.deserialize(JSObject object) {
    return FileSystemFlushRequest(
      databaseId: object.databaseId,
      requestId: object.requestId,
    );
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

    if (buffer case final buffer?) {
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
      parameters: TypeCode.decodeValues(
        object[_UniqueFieldNames.parameters] as JSArray,
        object[_UniqueFieldNames.typeVector] as JSArrayBuffer?,
      ),
      returnRows: (object[_UniqueFieldNames.returnRows] as JSBoolean).toDart,
    );
  }

  @override
  MessageType<Message> get type => MessageType.runQuery;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.sql] = sql.toJS;
    object[_UniqueFieldNames.returnRows] = returnRows.toJS;

    if (parameters.isNotEmpty) {
      final (array, types) = TypeCode.encodeValues(parameters);

      object[_UniqueFieldNames.parameters] = array;
      object[_UniqueFieldNames.typeVector] = types;
      transferred.add(types);
    } else {
      object[_UniqueFieldNames.parameters] = JSArray();
    }
  }
}

final class CloseDatabase extends Request {
  CloseDatabase({required super.requestId, required super.databaseId});

  factory CloseDatabase.deserialize(JSObject object) {
    return CloseDatabase(
        requestId: object.requestId, databaseId: object.databaseId);
  }

  @override
  MessageType<Message> get type => MessageType.closeDatabase;
}

final class OpenAdditonalConnection extends Request {
  OpenAdditonalConnection({
    required super.requestId,
    super.databaseId,
  });

  factory OpenAdditonalConnection.deserialize(JSObject object) {
    return OpenAdditonalConnection(
      requestId: object.requestId,
      databaseId: object.databaseId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.openAdditionalConnection;
}

@JS('ArrayBuffer')
external JSFunction get _arrayBufferConstructor;

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

    if (response.instanceof(_arrayBufferConstructor)) {
      transferred.add(response as JSObject);
    }
  }
}

final class EndpointResponse extends Response {
  final WebEndpoint endpoint;

  EndpointResponse({required super.requestId, required this.endpoint});

  factory EndpointResponse.deserialize(JSObject object) {
    return EndpointResponse(
      requestId: object.requestId,
      endpoint: object[_UniqueFieldNames.responseData] as WebEndpoint,
    );
  }

  @override
  MessageType<Message> get type => MessageType.endpointResponse;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.responseData] = endpoint;
    transferred.add(endpoint.port);
  }
}

enum TypeCode {
  unknown,
  integer,
  bigInt,
  float,
  text,
  blob,
  $null,
  boolean;

  static TypeCode of(int i) {
    return i >= TypeCode.values.length ? TypeCode.unknown : TypeCode.values[i];
  }

  Object? decodeColumn(JSAny? column) {
    const hasNativeInts = !identical(0, 0.0);

    return switch (this) {
      TypeCode.unknown => column.dartify(),
      TypeCode.integer => (column as JSNumber).toDartInt,
      TypeCode.bigInt => hasNativeInts
          ? (column as JsBigInt).asDartInt
          : (column as JsBigInt).asDartBigInt,
      TypeCode.float => (column as JSNumber).toDartDouble,
      TypeCode.text => (column as JSString).toDart,
      TypeCode.blob => (column as JSUint8Array).toDart,
      TypeCode.boolean => (column as JSBoolean).toDart,
      TypeCode.$null => null,
    };
  }

  static (TypeCode, JSAny?) encodeValue(Object? dart) {
    // In previous clients/workers, values were encoded with dartify() and
    // jsify() only. For backwards-compatibility, this value must be compatible
    // with dartify() used on the other end.
    // An exception are BigInts, which have not been sent correctly before this
    // encoder.
    // The reasons for adopting a custom format are: Being able to properly
    // serialize BigInts, possible dartify/jsify incompatibilities between
    // dart2js and dart2wasm and most importantly, being able to keep 1 and 1.0
    // apart in dart2wasm when the worker is compiled with dart2js.
    final JSAny? value;
    final TypeCode code;

    switch (dart) {
      case null:
        value = null;
        code = TypeCode.$null;
      case final int integer:
        value = integer.toJS;
        code = TypeCode.integer;
      case final BigInt bi:
        value = JsBigInt.fromBigInt(bi);
        code = TypeCode.bigInt;
      case final double d:
        value = d.toJS;
        code = TypeCode.float;
      case final String s:
        value = s.toJS;
        code = TypeCode.text;
      case final Uint8List blob:
        value = blob.toJS;
        code = TypeCode.blob;
      case final bool boolean:
        value = boolean.toJS;
        code = TypeCode.boolean;
      case final other:
        value = other.jsify();
        code = TypeCode.unknown;
    }

    return (code, value);
  }

  static (JSArray, JSArrayBuffer) encodeValues(List<Object?> values) {
    final jsParams = <JSAny?>[];
    final typeCodes = Uint8List(values.length);
    for (var i = 0; i < values.length; i++) {
      final (code, jsParam) = TypeCode.encodeValue(values[i]);
      typeCodes[i] = code.index;
      jsParams.add(jsParam);
    }

    final jsTypes = typeCodes.buffer.toJS;
    return (jsParams.toJS, jsTypes);
  }

  static List<Object?> decodeValues(JSArray array, JSArrayBuffer? types) {
    final rawParameters = array.toDart;
    final typeVector = types?.toDart.asUint8List();

    final parameters = List<Object?>.filled(rawParameters.length, null);
    for (var i = 0; i < parameters.length; i++) {
      final typeCode =
          typeVector != null ? TypeCode.of(typeVector[i]) : TypeCode.unknown;
      parameters[i] = typeCode.decodeColumn(rawParameters[i]);
    }

    return parameters;
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

    final typeVector = switch (object[_UniqueFieldNames.typeVector]) {
      final types? => (types as JSArrayBuffer).toDart.asUint8List(),
      null => null,
    };
    final rows = <List<Object?>>[];
    var i = 0;
    for (final row in (object[_UniqueFieldNames.rows] as JSArray).toDart) {
      final dartRow = <Object?>[];

      for (final column in (row as JSArray).toDart) {
        final typeCode =
            typeVector != null ? TypeCode.of(typeVector[i]) : TypeCode.unknown;
        dartRow.add(typeCode.decodeColumn(column));
        i++;
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
    final jsRows = <JSArray>[];
    final columns = resultSet.columnNames.length;
    final typeVector = Uint8List(resultSet.length * columns);

    for (var i = 0; i < resultSet.length; i++) {
      final row = resultSet.rows[i];
      assert(row.length == columns);
      final jsRow = List<JSAny?>.filled(row.length, null);

      for (var j = 0; j < columns; j++) {
        final (code, value) = TypeCode.encodeValue(row[j]);

        jsRow[j] = value;
        typeVector[i * columns + j] = code.index;
      }

      jsRows.add(jsRow.toJS);
    }

    final jsTypes = typeVector.buffer.toJS;
    object[_UniqueFieldNames.typeVector] = jsTypes;
    transferred.add(jsTypes);

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

  /// We can't send Dart objects over web channels, but we're serializing the
  /// most common exception types so that we can reconstruct them on the other
  /// end.
  final Object? serializedException;

  ErrorResponse({
    required this.message,
    required super.requestId,
    this.serializedException,
  });

  factory ErrorResponse.deserialize(JSObject object) {
    Object? serializedException;
    if (object.has(_UniqueFieldNames.serializedExceptionType)) {
      serializedException = switch (
          (object[_UniqueFieldNames.serializedExceptionType] as JSNumber)
              .toDartInt) {
        _typeSqliteException => deserializeSqliteException(
            object[_UniqueFieldNames.serializedException] as JSArray),
        _ => null,
      };
    }

    return ErrorResponse(
      message: (object[_UniqueFieldNames.errorMessage] as JSString).toDart,
      requestId: object.requestId,
      serializedException: serializedException,
    );
  }

  @override
  MessageType<Message> get type => MessageType.errorResponse;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.errorMessage] = message.toJS;

    if (serializedException case final SqliteException e?) {
      object[_UniqueFieldNames.serializedExceptionType] =
          _typeSqliteException.toJS;
      object[_UniqueFieldNames.serializedException] =
          serializeSqliteException(e);
    }
  }

  @override
  RemoteException interpretAsError() {
    return RemoteException(message: message, exception: serializedException);
  }

  static SqliteException deserializeSqliteException(JSArray data) {
    final [
      message,
      explanation,
      extendedResultCode,
      operation,
      causingStatement,
      paramData,
      paramTypes,
      ..._,
    ] = data.toDart;

    String? decodeNullableString(JSAny? jsValue) {
      if (jsValue.isDefinedAndNotNull) {
        return (jsValue as JSString).toDart;
      }
      return null;
    }

    return SqliteException(
      (extendedResultCode as JSNumber).toDartInt,
      (message as JSString).toDart,
      decodeNullableString(explanation),
      decodeNullableString(causingStatement),
      paramData.isDefinedAndNotNull && paramTypes.isDefinedAndNotNull
          ? TypeCode.decodeValues(
              paramData as JSArray, paramTypes as JSArrayBuffer)
          : null,
      decodeNullableString(operation),
    );
  }

  static JSArray serializeSqliteException(SqliteException e) {
    final params = switch (e.parametersToStatement) {
      null => null,
      final parameters => TypeCode.encodeValues(parameters),
    };

    return [
      e.message.toJS,
      e.explanation?.toJS,
      e.extendedResultCode.toJS,
      e.operation?.toJS,
      e.causingStatement?.toJS,
      params?.$1,
      params?.$2,
    ].toJS;
  }

  static const _typeSqliteException = 0;
}

final class StreamRequest extends Request {
  /// When true, the client is requesting to be informed about updates happening
  /// on the database identified by this request.
  ///
  /// When false, the client is requesting to no longer be informed about these
  /// updates.
  final bool action;

  @override
  final MessageType<Message> type;

  StreamRequest({
    required this.type,
    required this.action,
    required super.requestId,
    required super.databaseId,
  });

  factory StreamRequest.deserialize(
      MessageType<Message> type, JSObject object) {
    return StreamRequest(
      type: type,
      action: (object[_UniqueFieldNames.action] as JSBoolean).toDart,
      requestId: object.requestId,
      databaseId: object.databaseId,
    );
  }

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.action] = action.toJS;
  }
}

class CompatibilityCheck extends Request {
  @override
  final MessageType<CompatibilityCheck> type;

  final String? databaseName;

  CompatibilityCheck({
    required super.requestId,
    required this.type,
    required this.databaseName,
  });

  factory CompatibilityCheck.deserialize(
      MessageType<CompatibilityCheck> type, JSObject object) {
    return CompatibilityCheck(
      type: type,
      requestId: object.requestId,
      databaseName:
          (object[_UniqueFieldNames.databaseName] as JSString?)?.toDart,
    );
  }

  bool get shouldCheckOpfsCompatibility {
    return type == MessageType.dedicatedCompatibilityCheck ||
        type == MessageType.dedicatedInSharedCompatibilityCheck;
  }

  bool get shouldCheckIndexedDbCompatbility {
    return type == MessageType.dedicatedCompatibilityCheck ||
        type == MessageType.sharedCompatibilityCheck;
  }

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.databaseName] = databaseName?.toJS;
  }
}

final class CompatibilityResult {
  final List<ExistingDatabase> existingDatabases;

  // Fields set when a shared worker replies.

  /// Whether shared workers are allowed to spawn dedicated workers.
  ///
  /// As far as the web standard goes, they're supposed to. It allows us to
  /// spawn a dedicated worker using OPFS in the context of a shared worker,
  /// which is a very reliable storage implementation. Sadly, only Firefox has
  /// implemented this feature.
  final bool sharedCanSpawnDedicated;

  /// Whether dedicated workers can use OPFS.
  ///
  /// The file system API is only available in dedicated workers, so if they
  /// can't use it, the browser just likely doesn't support that API.
  final bool canUseOpfs;

  /// Whether IndexedDB is available to shared workers.
  ///
  /// On some browsers, IndexedDB is not available in private/incognito tabs.
  final bool canUseIndexedDb;

  /// Whether dedicated workers can use shared array buffers and the atomics
  /// API.
  ///
  /// This is required for the synchronous channel used to host an OPFS
  /// filesystem between threads. However, it is only available when the page is
  /// served with special headers for security purposes.
  final bool supportsSharedArrayBuffers;

  /// Whether dedicated workers can spawn their own dedicated workers.
  ///
  /// We need two dedicated workers with a synchronous channel between them to
  /// host an OPFS filesystem.
  final bool dedicatedWorkersCanNest;

  CompatibilityResult({
    required this.existingDatabases,
    required this.sharedCanSpawnDedicated,
    required this.canUseOpfs,
    required this.canUseIndexedDb,
    required this.supportsSharedArrayBuffers,
    required this.dedicatedWorkersCanNest,
  });

  factory CompatibilityResult.fromJS(JSObject result) {
    final existing = <ExistingDatabase>[];

    final encodedExisting = (result['a'] as JSArray<JSString>).toDart;
    for (var i = 0; i < encodedExisting.length / 2; i++) {
      final mode = StorageMode.values.byName(encodedExisting[i * 2].toDart);
      final name = encodedExisting[i * 2 + 1].toDart;

      existing.add((mode, name));
    }

    return CompatibilityResult(
      existingDatabases: existing,
      sharedCanSpawnDedicated: (result['b'] as JSBoolean).toDart,
      canUseOpfs: (result['c'] as JSBoolean).toDart,
      canUseIndexedDb: (result['d'] as JSBoolean).toDart,
      supportsSharedArrayBuffers: (result['e'] as JSBoolean).toDart,
      dedicatedWorkersCanNest: (result['f'] as JSBoolean).toDart,
    );
  }

  JSObject get toJS {
    final encodedDatabases = <JSString>[
      for (final existing in existingDatabases) ...[
        existing.$1.name.toJS,
        existing.$2.toJS
      ],
    ];

    return JSObject()
      ..['a'] = encodedDatabases.toJS
      ..['b'] = sharedCanSpawnDedicated.toJS
      ..['c'] = canUseOpfs.toJS
      ..['d'] = canUseIndexedDb.toJS
      ..['e'] = supportsSharedArrayBuffers.toJS
      ..['f'] = dedicatedWorkersCanNest.toJS;
  }
}

final class UpdateNotification extends Notification {
  final SqliteUpdate update;
  final int databaseId;

  UpdateNotification({required this.update, required this.databaseId});

  factory UpdateNotification.deserialize(JSObject object) {
    return UpdateNotification(
      update: SqliteUpdate(
        SqliteUpdateKind.values[
            (object[_UniqueFieldNames.updateKind] as JSNumber).toDartInt],
        (object[_UniqueFieldNames.updateTableName] as JSString).toDart,
        (object[_UniqueFieldNames.updateRowId] as JSNumber).toDartInt,
      ),
      databaseId: object.databaseId,
    );
  }

  @override
  MessageType<Message> get type => MessageType.notifyUpdate;

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.databaseId] = databaseId.toJS;
    object[_UniqueFieldNames.updateKind] = update.kind.index.toJS;
    object[_UniqueFieldNames.updateTableName] = update.tableName.toJS;
    object[_UniqueFieldNames.updateRowId] = update.rowId.toJS;
  }
}

/// Used as a notification without a payload, e.g. for commit or rollback
/// events.
final class EmptyNotification extends Notification {
  final int databaseId;
  @override
  final MessageType<Message> type;

  EmptyNotification({required this.type, required this.databaseId});

  factory EmptyNotification.deserialize(
      MessageType<Message> type, JSObject object) {
    return EmptyNotification(
      type: type,
      databaseId: object.databaseId,
    );
  }

  @override
  void serialize(JSObject object, List<JSObject> transferred) {
    super.serialize(object, transferred);
    object[_UniqueFieldNames.databaseId] = databaseId.toJS;
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

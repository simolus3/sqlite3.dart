import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
// ignore: implementation_imports
import 'package:sqlite3/src/wasm/js_interop/core.dart';

import '../channel.dart';
import 'dsl.dart';

@abstract
extension type Message._(JSObject _) implements JSObject {
  @JS(_UniqueFieldNames.type)
  @isType
  external String type;
}

@abstract
extension type Notification._(JSObject _) implements Message {
  @JS(_UniqueFieldNames.databaseId)
  external int databaseId;
}

@abstract
extension type Request._(JSObject _) implements Message {
  /// A unique id, incremented by each endpoint when making requests over the
  /// channel.
  @JS(_UniqueFieldNames.id)
  external int requestId;

  @JS(_UniqueFieldNames.databaseId)
  external int? databaseId;
}

@abstract
extension type Response._(JSObject _) implements Message {
  /// The [Request.requestId] that this is a response of.
  @JS(_UniqueFieldNames.id)
  external int requestId;
}

enum FileSystemImplementation {
  opfsShared('s'),
  opfsAtomics('l'),
  opfsExternalLocks('x'),
  indexedDb('i'),
  inMemory('m');

  final String jsRepresentation;

  const FileSystemImplementation(this.jsRepresentation);

  JSString get toJS => jsRepresentation.toJS;

  bool get needsExternalLocks =>
      // Technically, opfsAtomics doesn't need external locks around each
      // database access. We just do this to avoid contention in the underlying
      // VFS.
      this == opfsAtomics || this == opfsExternalLocks;

  static FileSystemImplementation fromJS(JSString js) {
    final toDart = js.toDart;

    for (final entry in values) {
      if (entry.jsRepresentation == toDart) return entry;
    }

    throw ArgumentError('Unknown FS implementation: $toDart');
  }
}

@MessageTypeName('open')
extension type OpenRequest._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.wasmUri)
  external String wasmUri;

  @JS(_UniqueFieldNames.databaseName)
  external String databaseName;
  @JS(_UniqueFieldNames.storageMode)
  external JSString storageMode;
  @JS(_UniqueFieldNames.onlyOpenVfs)
  external bool onlyOpenVfs;

  /// Additional data passsed to `DatabaseController.openDatabase`.
  @JS(_UniqueFieldNames.additionalData)
  external JSAny? additionalData;
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
@MessageTypeName('connect')
extension type ConnectRequest._(JSObject _) implements Request {
  /// The endpoint under which the client is reachable.
  @JS(_UniqueFieldNames.responseData)
  @transfer
  external WebEndpoint endpoint;
}

@MessageTypeName('startFileSystemServer')
extension type StartFileSystemServer._(JSObject _) implements Message {
  @JS(_UniqueFieldNames.additionalData)
  external WorkerOptions options;
}

/// Allows users of this package to implement their own RPC calls handled by
/// workers hosting the database.
@MessageTypeName('custom')
extension type CustomRequest._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.responseData)
  external JSAny? payload;
}

/// The other side will respond with a [SimpleSuccessResponse] containing a
/// boolean indicating whether the file exists.
@MessageTypeName('fileSystemExists')
extension type FileSystemExistsQuery._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.fileType)
  external int fsType;
}

@MessageTypeName('fileSystemFlush')
extension type FileSystemFlushRequest._(JSObject _) implements Request {}

@MessageTypeName('fileSystemAccess')
extension type FileSystemAccess._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.buffer)
  @transfer
  external JSArrayBuffer? buffer;
  @JS(_UniqueFieldNames.fileType)
  external int fsType;
}

@MessageTypeName('runQuery')
extension type RunQuery._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.sql)
  external String sql;

  @JS(_UniqueFieldNames.parameters)
  external JSArray parameters;
  @JS(_UniqueFieldNames.typeVector)
  @transfer
  external JSArrayBuffer? typeVector;

  @JS(_UniqueFieldNames.lockId)
  external int? lockId;
  @JS(_UniqueFieldNames.returnRows)
  external bool returnRows;
  @JS(_UniqueFieldNames.checkInTransaction)
  external bool checkInTransaction;
}

@MessageTypeName('exclusiveLock')
extension type RequestExclusiveLock._(JSObject _) implements Request {}

@MessageTypeName('releaseLock')
extension type ReleaseLock._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.lockId)
  external int lockId;
}

@MessageTypeName('closeDatabase')
extension type CloseDatabase._(JSObject _) implements Request {}

@MessageTypeName('openAdditionalConnection')
extension type OpenAdditionalConnection._(JSObject _) implements Request {}

@MessageTypeName('simpleSuccessResponse')
extension type SimpleSuccessResponse._(JSObject _) implements Response {
  @JS(_UniqueFieldNames.responseData)
  @transferIfArrayBuffer
  external JSAny? response;
}

@MessageTypeName('endpointResponse')
extension type EndpointResponse._(JSObject _) implements Response {
  @JS(_UniqueFieldNames.responseData)
  @transfer
  external WebEndpoint endpoint;
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
      TypeCode.bigInt =>
        hasNativeInts
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
      final typeCode = typeVector != null
          ? TypeCode.of(typeVector[i])
          : TypeCode.unknown;
      parameters[i] = typeCode.decodeColumn(rawParameters[i]);
    }

    return parameters;
  }
}

@MessageTypeName('rowsResponse')
extension type RowsResponse._(JSObject _) implements Response {
  @JS(_UniqueFieldNames.columnNames)
  external JSArray<JSString>? columnNames;
  @JS(_UniqueFieldNames.tableNames)
  external JSArray<JSString?>? tableNames;
  @JS(_UniqueFieldNames.typeVector)
  @transfer
  external JSArrayBuffer? typeVector;
  @JS(_UniqueFieldNames.rows)
  external JSArray<JSArray<JSAny?>>? rows;

  @JS(_UniqueFieldNames.autocommit)
  external bool autoCommit;
  @JS(_UniqueFieldNames.lastInsertRowid)
  external int lastInsertRowId;
}

@MessageTypeName('errorResponse')
extension type ErrorResponse._(JSObject _) implements Response {
  @JS(_UniqueFieldNames.errorMessage)
  external String message;

  @JS(_UniqueFieldNames.serializedExceptionType)
  external JSNumber? serializedExceptionType;

  @JS(_UniqueFieldNames.serializedException)
  external JSAny? serializedException;
}

@abstract
extension type StreamRequest._(JSObject _) implements Request {
  /// When true, the client is requesting to be informed about updates happening
  /// on the database identified by this request.
  ///
  /// When false, the client is requesting to no longer be informed about these
  /// updates.
  @JS(_UniqueFieldNames.action)
  external bool action;
}

@MessageTypeName('updateRequest')
extension type UpdateStreamRequest._(JSObject _) implements StreamRequest {}

@MessageTypeName('rollbackRequest')
extension type RollbackStreamRequest._(JSObject _) implements StreamRequest {}

@MessageTypeName('commitRequest')
extension type CommitsStreamRequest._(JSObject _) implements StreamRequest {}

@abstract
extension type CompatibilityCheck._(JSObject _) implements Request {
  @JS(_UniqueFieldNames.databaseName)
  external String? databaseName;
}

@MessageTypeName('dedicatedCompatibilityCheck')
extension type DedicatedCompatibilityCheck._(JSObject _)
    implements CompatibilityCheck {}

@MessageTypeName('sharedCompatibilityCheck')
extension type SharedCompatibilityCheck._(JSObject _)
    implements CompatibilityCheck {}

@MessageTypeName('dedicatedInSharedCompatibilityCheck')
extension type DedicatedInSharedCompatibilityCheck._(JSObject _)
    implements CompatibilityCheck {}

@MessageTypeName('notifyUpdate')
extension type UpdateNotification._(JSObject _) implements Notification {
  @JS(_UniqueFieldNames.updateKind)
  external int updateKind;
  @JS(_UniqueFieldNames.updateTableName)
  external String updateTableName;
  @JS(_UniqueFieldNames.updateRowId)
  external int rowId;
}

@MessageTypeName('notifyCommit')
extension type CommitNotification._(JSObject _) implements Notification {}

@MessageTypeName('notifyRollback')
extension type RollbackNotification._(JSObject _) implements Notification {}

/// Requests a previously issued request to be cancelled.
///
/// An endpoint will not respond to this message, but it may abort the previous
/// request by completing it with an error.
@MessageTypeName('abort')
extension type AbortRequest._(JSObject _) implements Message {
  @JS(_UniqueFieldNames.id)
  external int requestId;
}

/// Field names used when serializing messages to JS objects.
///
/// Since we're using unsafe JS interop here, these can't be mangled by dart2js.
/// Thus, we should keep them short.
class _UniqueFieldNames {
  static const action = 'a'; // Only used in StreamRequest
  static const additionalData = 'a'; // only used in OpenRequest
  static const buffer = 'b';
  // no clash, used in RowResponse and RunQuery
  static const columnNames = 'c';
  static const checkInTransaction = 'c';
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
  static const autocommit = 'x';
  static const lastInsertRowid = 'y';
  static const lockId = 'z';
}

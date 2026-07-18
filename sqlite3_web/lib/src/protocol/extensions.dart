import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' show MessagePort;

import '../js_array_buffer.dart';
import '../types.dart';
import '../worker_connector.dart';
import 'helper.g.dart';
import 'messages.dart';

extension MessageUtils on Message {
  void sendToPort(MessagePort port) {
    final transfer = extractTransferrable(this);
    port.postMessage(this, transfer);
  }

  void sendToWorker(WorkerHandle port) {
    final transfer = extractTransferrable(this);
    port.postMessage(this, transfer);
  }
}

extension ResponseUtils on Response {
  RemoteException interpretAsError() {
    if (type == MessageType.errorResponse.name) {
      final asError = this as ErrorResponse;
      final exception = asError.deserializeException();

      if (exception case final AbortException e?) {
        return e;
      } else {
        return RemoteException(message: asError.message, exception: exception);
      }
    } else {
      return RemoteException(
        message: 'Did not respond with expected type, got $this',
      );
    }
  }
}

extension ErrorResponseUtils on ErrorResponse {
  static ErrorResponse wrapException(int requestId, Object error) {
    JSNumber? serializedExceptionType;
    JSAny? serializedException;

    if (error is SqliteException) {
      serializedExceptionType = _typeSqliteException.toJS;
      serializedException = serializeSqliteException(error);
    } else if (error is AbortException) {
      serializedExceptionType = _typeAbortException.toJS;
    }

    return newErrorResponse(
      message: error.toString(),
      serializedExceptionType: serializedExceptionType,
      serializedException: serializedException,
      requestId: requestId,
    );
  }

  Object? deserializeException() {
    return switch (serializedExceptionType?.toDartInt) {
      _typeSqliteException => deserializeSqliteException(
        serializedException as JSArray,
      ),
      _typeAbortException => const AbortException(),
      _ => null,
    };
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
      offset,
      ..._,
    ] = data.toDart;

    String? decodeNullableString(JSAny? jsValue) {
      if (jsValue.isDefinedAndNotNull) {
        return (jsValue as JSString).toDart;
      }
      return null;
    }

    return SqliteException(
      extendedResultCode: (extendedResultCode as JSNumber).toDartInt,
      message: (message as JSString).toDart,
      explanation: decodeNullableString(explanation),
      causingStatement: decodeNullableString(causingStatement),
      parametersToStatement:
          paramData.isDefinedAndNotNull && paramTypes.isDefinedAndNotNull
          ? TypeCode.decodeValues(
              paramData as JSArray,
              paramTypes as JSArrayBuffer,
            )
          : null,
      operation: decodeNullableString(operation),
      offset: (offset as JSNumber?)?.toDartInt,
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
      e.offset?.toJS,
    ].toJS;
  }

  static const _typeSqliteException = 0;
  static const _typeAbortException = 1;
}

extension UpdateNotificationUtils on UpdateNotification {
  SqliteUpdate get sqliteUpdate {
    return SqliteUpdate(
      SqliteUpdateKind.values[updateKind],
      updateTableName,
      rowId,
    );
  }
}

extension RowsResponseUtils on RowsResponse {
  @Deprecated('Use iterateAndEncodeResults instead')
  static RowsResponse wrapResultSet(
    int requestId, {
    required ResultSet resultSet,
    required bool autoCommit,
    required int lastInsertRowId,
  }) {
    final jsRows = JSArray<JSArray<JSAny?>>.withLength(resultSet.length);
    final columns = resultSet.columnNames.length;
    final typeVector = Uint8List(resultSet.length * columns);

    for (var i = 0; i < resultSet.length; i++) {
      final row = resultSet.rows[i];
      assert(row.length == columns);
      final jsRow = JSArray<JSAny?>.withLength(row.length);

      for (var j = 0; j < columns; j++) {
        final (code, value) = TypeCode.encodeValue(row[j]);

        jsRow[j] = value;
        typeVector[i * columns + j] = code.index;
      }

      jsRows[i] = jsRow;
    }

    JSArray<JSString?>? tableNames;
    if (resultSet.tableNames case var dartTableNames?) {
      tableNames = <JSString?>[
        for (final entry in dartTableNames) entry?.toJS,
      ].toJS;
    }

    return newRowsResponse(
      columnNames: <JSString>[
        for (final entry in resultSet.columnNames) entry.toJS,
      ].toJS,
      tableNames: tableNames,
      typeVector: typeVector.buffer.toJS,
      rows: jsRows,
      autoCommit: autoCommit,
      lastInsertRowId: lastInsertRowId,
      requestId: requestId,
    );
  }

  static RowsResponse iterateAndEncodeResults(
    CommonPreparedStatement statement,
    DecodedTypedValues parameters,
  ) {
    final jsRows = JSArray<JSArray<JSAny?>>();
    final types = GrowableArrayBuffer();
    final rawStmt = statement.raw;
    var columnCount = 0;

    parameters.bindAsParameters(statement);

    var isFirst = true;
    while (rawStmt.step()) {
      if (isFirst) {
        columnCount = rawStmt.columnCount;
        isFirst = false;
      }

      final typesForRow = types.newChunk(columnCount);
      final row = JSArray.withLength(columnCount);
      for (var i = 0; i < columnCount; i++) {
        JSAny? value;
        TypeCode code;

        switch (rawStmt.columnType(i)) {
          case SqlType.SQLITE_INTEGER:
            final bigInt = rawStmt.columnJSBigInt(i);
            final asJsNumber = _number(bigInt);
            if (_numberIsSafeInteger(asJsNumber).toDart) {
              value = asJsNumber;
              code = TypeCode.integer;
            } else {
              value = bigInt;
              code = TypeCode.bigInt;
            }
          case SqlType.SQLITE_FLOAT:
            value = rawStmt.columnDouble(i).toJS;
            code = TypeCode.float;
          case SqlType.SQLITE_TEXT:
            value = rawStmt.columnText(i).toJS;
            code = TypeCode.text;
          case SqlType.SQLITE_BLOB:
            value = rawStmt.columnBlob(i).toJS;
            code = TypeCode.blob;
          case SqlType.SQLITE_NULL:
          default:
            code = TypeCode.$null;
        }

        row[i] = value;
        typesForRow.setUint8(i, code.index);
      }

      jsRows.add(row);
    }

    final columnNames = JSArray<JSString>.withLength(columnCount);
    final tableNames = JSArray<JSString?>.withLength(columnCount);
    for (var i = 0; i < columnCount; i++) {
      columnNames[i] = rawStmt.columnName(i).toJS;
      tableNames[i] = rawStmt.columnTableName(i)?.toJS;
    }

    return newRowsResponse(
      columnNames: columnNames,
      tableNames: tableNames,
      typeVector: types.take(),
      rows: jsRows,
      autoCommit: false,
      lastInsertRowId: 0,
      requestId: 0,
    );
  }

  ResultSet? readResultSet() {
    if (columnNames case final rawColumnNames?) {
      final columnNames = rawColumnNames.toDart.map((e) => e.toDart).toList();
      final tableNames = this.tableNames?.toDart.map((e) => e?.toDart).toList();
      final typeVector = this.typeVector?.toDart.asUint8List();

      final rows = <List<Object?>>[];
      var i = 0;
      for (final row in this.rows!.toDart) {
        final dartRow = <Object?>[];

        for (final column in row.toDart) {
          final typeCode = typeVector != null
              ? TypeCode.of(typeVector[i])
              : TypeCode.unknown;
          dartRow.add(typeCode.decodeColumn(column));
          i++;
        }

        rows.add(dartRow);
      }

      return ResultSet(columnNames, tableNames, rows);
    } else {
      return null;
    }
  }
}

extension CompatibilityCheckUtils on CompatibilityCheck {
  bool get shouldCheckOpfsCompatibility {
    return type == MessageType.dedicatedCompatibilityCheck.name ||
        type == MessageType.dedicatedInSharedCompatibilityCheck.name;
  }

  bool get shouldCheckIndexedDbCompatbility {
    return type == MessageType.dedicatedCompatibilityCheck.name ||
        type == MessageType.sharedCompatibilityCheck.name;
  }
}

bool isCompatibilityCheck(String messageType) {
  if (messageType == MessageType.sharedCompatibilityCheck.name ||
      messageType == MessageType.dedicatedCompatibilityCheck.name ||
      messageType == MessageType.dedicatedInSharedCompatibilityCheck.name) {
    return true;
  } else {
    return false;
  }
}

@JS('Number')
external JSNumber _number(JSAny? e);

@JS('Number.isSafeInteger')
external JSBoolean _numberIsSafeInteger(JSAny? e);

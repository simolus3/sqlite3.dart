/// Utilities for encoding sqlite3 types across web message ports.
library;

export 'src/protocol/messages.dart' show DecodedTypedValues;

import 'dart:js_interop';

import 'package:sqlite3/wasm.dart';
import 'src/protocol.dart';

/// Serializes a list of [parameters] compatible with the sqlite3 package into
/// a pair of an [JSArrayBuffer] and a [JSArray].
///
/// The [JSArray] is backwards-compatible with clients calling `toDart` on the
/// array and `dartify()` on the entries.
/// However, the [JSArrayBuffer] provides out-of-band type information about
/// the entries in the array. When one of the communication partners was
/// compiled with dart2wasm, this is useful to tell integers and doubles apart
/// reliably.
(JSArray, JSArrayBuffer) serializeParameters(List<Object?> parameters) {
  return TypeCode.encodeValues(parameters);
}

/// Given an array of values and optionally also type information obtained from
/// [serializeParameters], return the parameters.
DecodedTypedValues deserializeParameters(JSArray values, JSArrayBuffer? types) {
  return TypeCode.decodeValues(values, types);
}

/// Serializes a [ResultSet] into a serializable [JSObject].
@Deprecated('Use runStatementAndEncodeResults instead')
JSObject serializeResultSet(ResultSet resultSet) {
  return RowsResponseUtils.wrapResultSet(
    0,
    resultSet: resultSet,
    autoCommit: false,
    lastInsertRowId: 0,
  );
}

/// Steps through the statement, encoding each row as a JavaScript value that
/// can later be deserialized with [deserializeResultSet].
///
/// This correctly preserves type information for numeric values. For example, a
/// double `3.0` would be encoded differently than the int `3`, allowing clients
/// where those values are non-identical (i.e., dart2wasm) to tell them apart.
JSObject runStatementAndEncodeResults(
  CommonPreparedStatement statement,
  DecodedTypedValues parameters,
) {
  return RowsResponseUtils.iterateAndEncodeResults(statement, parameters);
}

/// Deserializes a result set from the format in [serializeResultSet].
ResultSet deserializeResultSet(JSObject object) {
  return (object as RowsResponse).readResultSet()!;
}

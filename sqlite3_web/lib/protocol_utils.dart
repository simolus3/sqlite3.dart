/// Utilities for encoding sqlite3 types across web message ports.
library;

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
List<Object?> deserializeParameters(JSArray values, JSArrayBuffer? types) {
  return TypeCode.decodeValues(values, types);
}

/// Serializes a [ResultSet] into a serializable [JSObject].
JSObject serializeResultSet(ResultSet resultSet) {
  final msg = JSObject();
  RowsResponse.serializeResultSet(msg, [], resultSet);
  return msg;
}

/// Deserializes a result set from the format in [serializeResultSet].
ResultSet deserializeResultSet(JSObject object) {
  return RowsResponse.deserializeResultSet(object);
}

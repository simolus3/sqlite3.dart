import '../constants.dart';
import 'bindings.dart';
import 'exception.dart';

extension BigIntRangeCheck on BigInt {
  BigInt get checkRange {
    if (this < bigIntMinValue64 || this > bigIntMaxValue64) {
      throw Exception('BigInt value exceeds the range of 64 bits');
    }
    return this;
  }
}

int eTextRep(bool deterministic, bool directOnly, bool subtype) {
  var flags = SqlTextEncoding.SQLITE_UTF8;
  if (deterministic) {
    flags |= SqlFunctionFlag.SQLITE_DETERMINISTIC;
  }
  if (directOnly) {
    flags |= SqlFunctionFlag.SQLITE_DIRECTONLY;
  }
  if (subtype) {
    flags |=
        SqlFunctionFlag.SQLITE_SUBTYPE | SqlFunctionFlag.SQLITE_RESULT_SUBTYPE;
  }

  return flags;
}

extension HandleResult<T> on SqliteResult<T> {
  T okOrThrowOutsideOfDatabase(RawSqliteBindings bindings) {
    if (resultCode != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, resultCode);
    }

    return result;
  }
}

extension ReadDartValue on RawSqliteValue {
  Object? read() {
    return switch (sqlite3_value_type()) {
      SqlType.SQLITE_INTEGER => sqlite3_value_int64(),
      SqlType.SQLITE_FLOAT => sqlite3_value_double(),
      SqlType.SQLITE_TEXT => sqlite3_value_text(),
      SqlType.SQLITE_BLOB => sqlite3_value_blob(),
      SqlType.SQLITE_BLOB || _ => null,
    };
  }
}

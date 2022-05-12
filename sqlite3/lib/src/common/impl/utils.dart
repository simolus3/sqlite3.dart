import '../constants.dart';
import '../sqlite3.dart';

int flagsForOpen({
  OpenMode mode = OpenMode.readWriteCreate,
  bool uri = false,
  bool? mutex,
}) {
  int flags;
  switch (mode) {
    case OpenMode.readOnly:
      flags = SqlFlag.SQLITE_OPEN_READONLY;
      break;
    case OpenMode.readWrite:
      flags = SqlFlag.SQLITE_OPEN_READWRITE;
      break;
    case OpenMode.readWriteCreate:
      flags = SqlFlag.SQLITE_OPEN_READWRITE | SqlFlag.SQLITE_OPEN_CREATE;
      break;
  }

  if (uri) {
    flags |= SqlFlag.SQLITE_OPEN_URI;
  }

  if (mutex != null) {
    flags |=
        mutex ? SqlFlag.SQLITE_OPEN_FULLMUTEX : SqlFlag.SQLITE_OPEN_NOMUTEX;
  }

  return flags;
}

int eTextRep(bool deterministic, bool directOnly) {
  var flags = SqlTextEncoding.SQLITE_UTF8;
  if (deterministic) {
    flags |= SqlFunctionFlag.SQLITE_DETERMINISTIC;
  }
  if (directOnly) {
    flags |= SqlFunctionFlag.SQLITE_DIRECTONLY;
  }

  return flags;
}

extension BigIntRangeCheck on BigInt {
  BigInt get checkRange {
    if (this < bigIntMinValue64 || this > bigIntMaxValue64) {
      throw Exception('BigInt value exceeds the range of 64 bits');
    }
    return this;
  }
}

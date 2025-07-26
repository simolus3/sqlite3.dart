import '../constants.dart';

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

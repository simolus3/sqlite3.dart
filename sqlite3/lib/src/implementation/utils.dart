import '../constants.dart';

extension BigIntRangeCheck on BigInt {
  BigInt get checkRange {
    if (this < bigIntMinValue64 || this > bigIntMaxValue64) {
      throw Exception('BigInt value exceeds the range of 64 bits');
    }
    return this;
  }
}

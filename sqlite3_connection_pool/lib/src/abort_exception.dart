/// An exception signalling that a request on a pool has been aborted.
@pragma('vm:deeply-immutable')
final class PoolAbortException implements Exception {
  const PoolAbortException();

  @override
  String toString() {
    return 'PoolAbortException: A request on a pool was aborted because the '
        'passed abort future completed';
  }
}

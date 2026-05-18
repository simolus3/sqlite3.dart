/// Whether to support binding [BigInt] values.
///
/// This is enabled by default, and disabling it is experimental. This is mainly
/// relevant for web workers, which don't really benefit from using [BigInt]
/// values internally:
///
///  - Over the wire, we receive values as `JSBigInt`.
///  - To bind values to SQLite, we need to use `JSBigInt` as well.
///
/// By removing support for [BigInt]s and their conversion to `JSBigInt`, we
/// save around 20kb from the default worker with `dart compile js -O4`.
const supportDartBigInts = bool.fromEnvironment(
  'sqlite3.dartbigints',
  defaultValue: true,
);

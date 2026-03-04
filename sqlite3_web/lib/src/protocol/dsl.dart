import 'package:meta/meta_meta.dart';

/// Annotation on protocol messages that can't be instantiated.
const abstract = 'abstract';

/// Annotation on protocol fields to indicate that they need to be passed in the
/// transfer array of `postMessage` calls to e.g. transfer typed buffers.
const transfer = 'transfer';

/// Like [transfer], but for `JSAny` types that should only be transferred if
/// they're array buffers.
const transferIfArrayBuffer = 'transferIfArrayBuffer';

/// Marker for the `Message.type` special field.
const isType = 'is:type';

/// Name of the message type used in the protocol.
@Target({TargetKind.extensionType})
final class MessageTypeName {
  final String name;

  const MessageTypeName(this.name);
}

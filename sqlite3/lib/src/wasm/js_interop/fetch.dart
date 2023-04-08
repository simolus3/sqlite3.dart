import 'package:js/js.dart';

@JS()
@staticInterop
class URL {
  external factory URL.absolute(String url);
  external factory URL.relative(String url, String base);
}

@JS()
@anonymous
class FetchOptions {
  external factory FetchOptions({
    String? method,
    Object? headers,
  });
}

@JS()
external Object fetch(URL resource, [FetchOptions? options]);

@JS()
@anonymous
class ResponseInit {
  external factory ResponseInit(
      {int? status, String? statusText, Object? headers});
}

@JS()
@staticInterop
class Response {
  external factory Response(
      Object /* Blob|BufferSource|FormData|ReadableStream|URLSearchParams|UVString */
          body,
      ResponseInit init);
}

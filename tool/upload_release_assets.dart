import 'dart:io';

import 'package:http/http.dart';
import 'package:sqlite3/src/hook/asset_hashes.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

/// Uploads assets we attach to GitHub releases to Bunny Storage.
///
/// This runs whenever the `sqlite3` package is released.
void main(List<String> args) async {
  final dir = Directory(switch (args) {
    [final path] => path,
    _ => throw ArgumentError(
      'Usage: BUNNY_URL=... BUNNY_ACCESS_KEY=... dart run tool/upload_release_assets.dart <directory>',
    ),
  });

  final uploader = _AssetUploader(
    Uri.parse(_readEnv('BUNNY_URL')),
    _readEnv('BUNNY_ACCESS_KEY'),
  );

  try {
    await uploader.uploadDirectory(dir);
  } finally {
    uploader.close();
  }
}

String _readEnv(String key) {
  final value = Platform.environment[key];
  if (value == null || value.isEmpty) {
    throw ArgumentError('Missing environment variable: $key');
  }
  return value;
}

final class _AssetUploader {
  final client = Client();
  final uploadSemaphore = Pool(4);
  final Uri bunnyUrl;
  final String accessKey;

  _AssetUploader(this.bunnyUrl, this.accessKey);

  Future<void> uploadDirectory(Directory directory) async {
    final uploads = [
      for (final file in directory.listSync())
        if (file is File && !p.basename(file.path).startsWith('.'))
          uploadSemaphore.withResource(() => _uploadFile(file)),
    ];

    await uploads.wait;
    print('Uploaded ${uploads.length} files');
  }

  Future<void> _uploadFile(File file) async {
    final basename = p.basename(file.path);
    final uri = bunnyUrl.resolve('sqlite3/$releaseTag/$basename');
    final request = StreamedRequest('PUT', uri);
    request.contentLength = file.statSync().size;
    request.headers['AccessKey'] = accessKey;
    request.headers['Content-Type'] = 'application/octet-stream';
    if (assetNameToSha256Hash[basename] case final checksum?)
      request.headers['Checksum'] = checksum.toUpperCase();
    file.openRead().pipe(request.sink);

    final streamedResponse = await client.send(request);
    final response = await Response.fromStream(streamedResponse);
    if (response.statusCode != 201) {
      throw HttpException(
        'Unexpected status ${response.statusCode} ${response.reasonPhrase}: ${response.body}',
        uri: uri,
      );
    }

    print('Uploaded ${file.path}');
  }

  void close() => client.close();
}

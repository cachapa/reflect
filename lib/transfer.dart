import 'dart:async';
import 'dart:io';

import 'package:http/http.dart';
import 'package:reflect/metadata.dart';

import 'globals.dart';
import 'rest_client.dart';

class Transfer {
  final Uri address;
  final RestClient client;

  Transfer(this.address) : client = RestClient();

  Future<void> createDir(DirectoryMetadata metadata) async {
    final url = address.replace(
      path: '${address.path}/files/${metadata.relativePath}/',
    );
    final request = Request('PUT', url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      print('${response.statusCode} ${response.reasonPhrase}');
      return;
    }
  }

  Future<void> delete(Metadata metadata) async {
    final url = address.replace(
      path: '${address.path}/files/${metadata.relativePath}',
    );
    final request = Request('DELETE', url);
    final response = await client.send(
      request
        ..headers.addAll({
          'indexed': metadata.indexed.toIso8601String(),
        }),
    );
    if (response.statusCode != 200) {
      print('${response.statusCode} ${response.reasonPhrase}');
      return;
    }
  }

  Future<void> download(FileMetadata metadata) async {
    final url = address.replace(
      path: '${address.path}/files/${metadata.relativePath}',
    );
    final request = Request('GET', url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      print('${response.statusCode} ${response.reasonPhrase}');
      return;
    }

    final size = response.contentLength;
    print('⬇  $metadata…');

    final path = '$basePath/${metadata.relativePath}';
    final file = File('$path.reflect');
    await file.parent.create(recursive: true);

    // var progress = 0;
    var sink = file.openWrite();
    await response.stream
        // .map((bytes) {
        // progress += bytes.length;
        // print('${(progress / size * 100).toStringAsFixed(1)}%');
        // return bytes;
        // })
        .pipe(sink);
    await sink.flush();
    await sink.close();

    // Match the FS modification time to the metadata
    await file.setLastModified(metadata.modified);
    await file.rename(path);
  }

  Future<void> upload(FileMetadata metadata) async {
    final file = metadata.entity;
    if (!file.existsSync()) {
      print('⚠ Wanted to upload $metadata but the file does not exist');
      return;
    }

    final url = address.replace(
      path: '${address.path}/files/${metadata.relativePath}',
    );
    print('⬆  $metadata…');

    final size = file.lengthSync();

    final request = StreamedRequest('PUT', url)
      ..headers.addAll({
        HttpHeaders.contentLengthHeader: '$size',
        'indexed': metadata.indexed.toIso8601String(),
        'modified': metadata.modified.toIso8601String(),
      });

    var progress = 0;
    final sub = file.openRead().listen(
      (bytes) {
        progress += bytes.length;
        // print(size == 0 ? '100%' : (progress / size).asPercentage);
        request.sink.add(bytes);
      },
      onDone: () => request.sink.close(),
      onError: (e) => print('Error: $e'),
    );

    // file.readAsBytesSync();
    // request.sink.close();

    final response = await client.send(request);
    // await sub.cancel();

    if (response.statusCode != 200) {
      print('${response.statusCode} ${response.reasonPhrase}');
    }
  }
}

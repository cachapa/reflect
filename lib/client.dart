import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:reflect/indexer.dart';
import 'package:reflect/rest_client.dart';

import 'metadata.dart';

class Client {
  final Indexer indexer;
  final Uri address;
  late final client = RestClient(null);

  Client(this.indexer, String address) : address = Uri.parse(address);

  Future<void> sync() async {
    final result = await client.post(
        address.replace(path: '${address.path}/sync'),
        body: indexer.toJson());

    final changes =
        (jsonDecode(result.body) as Map<String, dynamic>).cast<String, List>();
    final serverChanges = changes['server_changes']!
        .cast<Map<String, dynamic>>()
        .map(Metadata.fromMap);
    final clientChanges = changes['client_changes']!
        .cast<Map<String, dynamic>>()
        .map(Metadata.fromMap);

    // indexer.values.whereType<FileMetadata>().where((e) => !e.isDeleted).forEach(
    //   (e) {
    //     final file = indexer.getFile(e);
    //     print('$e ${file.statSync().changed}');
    //   },
    // );
    // return;

    // print('recv $serverChanges');
    // print('send $clientChanges');

    // Apply server changes locally
    for (final change in serverChanges) {
      switch (change) {
        case final DirectoryMetadata change:
          final dir = change.entity(indexer.path);
          if (change.isDeleted) {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          } else {
            if (!dir.existsSync()) dir.createSync();
          }
        case FileMetadata():
          if (change.isDeleted) {
            final file = indexer.getFile(change);
            if (file.existsSync()) change.entity(indexer.path).deleteSync();
          } else {
            await download(change);
          }
      }
      await indexer.put(change);
    }

    // Apply local changes to server
    for (final change in clientChanges) {
      await upload(change as FileMetadata);
    }
  }

  // Future<void> _mergeNext() async {
  //   if (!_connected || _synchronizing) return;
  //   _synchronizing = true;
  //
  //   final remoteChanges = remoteIndex.values
  //       .where((e) => e.isNewer(indexer.get(e.path)))
  //       .toList()
  //     ..sort();
  //
  //   final localChanges = indexer.values
  //       .where((e) => e.isNewer(remoteIndex[e.path]))
  //       .toList()
  //     ..sort();
  //
  //   if (remoteChanges.isNotEmpty) {
  //     final entry = remoteChanges.first;
  //     if (entry.isDeleted) {
  //       if (entry.entity('').existsSync()) {
  //         entry.entity('').deleteSync(recursive: true);
  //       }
  //       await indexer.put(entry);
  //     } else {
  //       if (entry is FileMetadata) {
  //         await _transfer.download(entry);
  //       } else if (!entry.entity('').existsSync()) {
  //         (entry.entity as Directory).createSync(recursive: true);
  //       }
  //     }
  //     // TODO Only index this file
  //     await indexer.index();
  //   } else if (localChanges.isNotEmpty) {
  //     final entry = localChanges.first;
  //     if (entry.isDeleted) {
  //       await _transfer.delete(entry);
  //     } else {
  //       if (entry is FileMetadata) {
  //         await _transfer.upload(entry);
  //       } else {
  //         await _transfer.createDir(entry as DirectoryMetadata);
  //       }
  //     }
  //     remoteIndex[entry.path] = entry;
  //   }
  //
  //   _synchronizing = false;
  //   if (remoteChanges.isNotEmpty || localChanges.isNotEmpty) {
  //     // ignore: unawaited_futures
  //     _mergeNext();
  //   }
  // }

  Future<void> download(FileMetadata metadata) async {
    final url = address.replace(
      path: '${address.path}/files/${metadata.path}',
    );
    final request = Request('GET', url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      print('${response.statusCode} ${response.reasonPhrase}');
      return;
    }

    final size = response.contentLength;
    print('⬇  $metadata…');

    final path = '${indexer.path}/${metadata.path}';
    final file = File('$path.reflecting');
    // await file.parent.create(recursive: true);

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
    final file = metadata.entity(indexer.path);
    if (!file.existsSync()) {
      print('⚠ Wanted to upload $metadata but the file does not exist');
      return;
    }

    final url = address.replace(
      path: '${address.path}/files/${metadata.path}',
    );
    print('⬆  $metadata…');

    final request = StreamedRequest('PUT', url)
      ..headers.addAll({
        HttpHeaders.contentLengthHeader: '${metadata.size}',
        'indexed': metadata.changed.toIso8601String(),
        'modified': metadata.modified.toIso8601String(),
        'md5': metadata.md5!,
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
      print(
          '${response.statusCode} ${response.reasonPhrase} ${await response.stream.bytesToString()}');
    }
  }
}

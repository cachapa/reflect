import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:reflect/util/extensions.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'indexer.dart';
import 'metadata.dart';

class Server {
  final Indexer indexer;
  final int port;

  Server(this.indexer, this.port);

  Future<void> serve() async {
    var router = Router()
      // ..get('/ws', _wsHandler)
      ..get('/manifest', _manifestHandler)
      ..post('/sync', _syncHandler)
      ..get('/files/<ignored|.*>', _getFilesHandler)
      ..put('/files/<ignored|.*>', _putFilesHandler)
      // ..patch('/files/<ignored|.*>', _moveFilesHandler)
      ..delete('/files/<ignored|.*>', _deleteFilesHandler)
      // ..get('/health', _healthHandler)
      // Return 404 for everything else
      ..all('/<ignored|.*>', _notFoundHandler);

    var handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_validateClock)
        .addHandler(router.call);

    var server = await io.serve(handler, '0.0.0.0', port);
    print('Listening on port ${server.port}…');

    // Wait for server to finish
    final completer = Completer();
    server.doOnDone(() => completer.complete());
    await completer.future;
  }

  FutureOr<Response> _wsHandler(Request request) {
    var handler = webSocketHandler((webSocket, _) async {
      print('Client connected to ${request.url.path}');

      webSocket.stream.listen(
        (_) {},
        onDone: () {
          print('Client disconnected from ${request.url.path}');
        },
      );

      // Send our index as handshake
      webSocket.sink.add(indexer.toJson());

      // Monitor changes
      // indexer.changes.listen((event) {
      //   webSocket.sink.add(jsonEncode([event]));
      // });
    });

    return handler(request);
  }

  Future<Response> _manifestHandler(Request request) async {
    await indexer.index();
    return Response.ok(indexer.toJson());
  }

  Future<Response> _syncHandler(Request request) async {
    await indexer.index();

    // Parse remote manifest
    final jsonManifest = await request.readAsString();
    final clientIndex = {
      for (final m in (jsonDecode(jsonManifest) as List)
          .cast<Map<String, dynamic>>()
          .map(Metadata.fromMap))
        m.path: m
    };

    // Identify changes required on both sides
    final clientChanges = clientIndex.values
        .where((c) => c.isNewer(indexer.get(c.path)))
        .toList()
      ..sort();
    final serverChanges = indexer.values
        .where((c) => c.isNewer(clientIndex[c.path]))
        // Filter out deleted directories if client has updates inside them
        .where(
          (c) => !(c is DirectoryMetadata &&
              c.isDeleted &&
              clientChanges
                  .any((e) => !e.isDeleted && e.path.startsWith(c.path))),
        )
        .toList()
      ..sort();

    print('server $serverChanges');
    print('client $clientChanges');

    final clientUploads = [];
    // Apply client changes that don't require file transfers
    for (final change in clientChanges) {
      switch (change) {
        case final DirectoryMetadata change:
          final dir = change.entity(indexer.path);
          if (change.isDeleted) {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          } else {
            if (!dir.existsSync()) dir.createSync(recursive: true);
          }
          await indexer.put(change);
        case FileMetadata():
          if (change.isDeleted) {
            final file = change.entity(indexer.path);
            if (file.existsSync()) file.deleteSync();
            await indexer.put(change);
          } else {
            // Detect duplicate files using md5
            final existing = indexer.getDuplicate(change);
            if (existing != null) {
              print(
                  'Skipping upload for $change. Using ${existing.relativePath(indexer.path)}.');
              final file = indexer.getFile(change);
              existing.copySync(file.path);
              file.setLastModifiedSync(change.modified);
              await indexer.put(change);
            } else {
              clientUploads.add(change);
            }
          }
      }
    }

    return Response.ok({
      'client_changes': clientUploads,
      'server_changes': serverChanges,
    }.toJson());
  }

  Response _getFilesHandler(Request request) {
    final path = Uri.decodeComponent(
        request.requestedUri.path.substring('/files/'.length));

    final file = File('${indexer.path}/$path');
    final type = lookupMimeType(path);

    if (file.existsSync()) {
      final size = file.lengthSync();
      return Response.ok(
        file.openRead(),
        headers: {
          HttpHeaders.contentLengthHeader: '$size',
          if (type != null) HttpHeaders.contentTypeHeader: type,
        },
      );
    } else {
      return _notFoundHandler(request);
    }
  }

  Future<Response> _putFilesHandler(Request request) async {
    final path = Uri.decodeComponent(
        request.requestedUri.path.substring('/files/'.length));

    // Reject upload if relative path leads outside of basepath
    final fullPath = '${indexer.path}/$path';
    if (!p.isWithin(indexer.path, fullPath)) {
      return Response.forbidden('Path leads outside shared directory.');
    }

    // Reject upload if file is already being transferred
    final tempFile = File('$fullPath.reflecting');
    if (tempFile.existsSync()) {
      return Response(409,
          body: 'File already being transferred by another client.');
    }

    final size = int.parse(request.headers[HttpHeaders.contentLengthHeader]!);
    final modified = DateTime.parse(request.headers['modified']!);
    final md5 = request.headers['md5']!;

    // Check if a local local file exists and is newer
    await indexer.index();
    final localMetadata = indexer.get(path);
    final remoteMetadata =
        FileMetadata(path, DateTime.now(), modified, size, md5, false);

    if (!remoteMetadata.isNewer(localMetadata)) {
      return Response(409,
          body: 'A newer version of this file already exists.');
    }

    tempFile.parent.createSync(recursive: true);
    final sink = tempFile.openWrite();
    await sink.addStream(request.read());
    await sink.close();

    // Verify received file
    if (tempFile.lengthSync() != size) {
      tempFile.deleteSync();
      return Response.badRequest(body: 'Received file failed size check.');
    }
    final receivedMd5 = await tempFile.md5;
    if (receivedMd5 != md5) {
      tempFile.deleteSync();
      return Response.badRequest(body: 'Received file failed md5 check.');
    }

    tempFile.setLastModifiedSync(modified);
    tempFile.renameSync(fullPath);

    await indexer.put(remoteMetadata);

    return Response.ok('Received $path (${size.asBytes})');
  }

  Future<Response> _moveFilesHandler(Request request) async {
    final relativePath = Uri.decodeComponent(
        request.requestedUri.path.substring('/files/'.length));
    final path = '$relativePath';
    if (!p.isWithin('', path)) {
      return Response.forbidden('Path is outside of share directory');
    }

    final entity = openEntity(path);
    if (!entity.existsSync()) {
      return Response.notFound('File not found');
    }

    final newPath = '${request.headers['new_path']}';
    if (!p.isWithin('', newPath)) {
      return Response.forbidden('New path is outside of share directory');
    }

    try {
      entity.renameSync(newPath);
    } catch (e) {
      return Response(400, body: e.toString());
    }
    return Response.ok('Renamed ${request.headers['new_path']}');
  }

  FutureOr<Response> _deleteFilesHandler(Request request) async {
    if (!request.headers.containsKey('indexed')) {
      return Response.forbidden('Missing modified header');
    }
    final indexed = DateTime.tryParse(request.headers['indexed']!);
    if (indexed == null) {
      return Response.forbidden(
          'Unrecognized clock format: ${request.headers['indexed']}');
    }

    final path = Uri.decodeComponent(
        request.requestedUri.path.substring('/files'.length));

    if (!p.isWithin(indexer.path, path)) {
      return Response.forbidden('Path is outside of share directory');
    }

    final local = indexer.get(path);
    final entity = openEntity(path);

    if (entity.existsSync() &&
        ((local != null && indexed.isAfter(local.changed)) || local == null)) {
      entity.deleteSync(recursive: true);
      await indexer.index();
    }

    return Response.ok('Deleted $path');
  }

  FutureOr<Response> _healthHandler(Request request) => Response.ok('👍');

  Response _notFoundHandler(Request request) => Response.notFound('Not found');

  Handler _validateClock(Handler innerHandler) => (request) {
        // Only check the clock on write operations
        if (request.method.toLowerCase() == 'get') return innerHandler(request);

        if (!request.headers.containsKey('clock')) {
          print('Missing clock header');
          return Response.forbidden('Missing clock header');
        }
        final remoteClock = DateTime.tryParse(request.headers['clock']!);
        if (remoteClock == null) {
          print('Unrecognized clock format: ${request.headers['clock']}');
          return Response.forbidden(
              'Unrecognized clock format: ${request.headers['clock']}');
        }
        final drift =
            DateTime.now().toLocal().difference(remoteClock.toLocal()).abs();
        if (drift.inMinutes >= 5) {
          print('Clock drift too large: $drift');
          return Response.forbidden('Clock drift too large: $drift');
        }
        return innerHandler(request);
      };
}

FileSystemEntity openEntity(String path) =>
    FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);

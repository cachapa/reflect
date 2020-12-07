import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:reflect/util/extensions.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'globals.dart';
import 'indexer.dart';

class Server {
  final Indexer indexer;
  final int port;

  Server(this.indexer, this.port);

  Future<void> serve() async {
    var router = Router()
      ..get('/ws', _wsHandler)
      ..get('/manifest', _manifestHandler)
      ..get('/files/<ignored|.*>', _getFilesHandler)
      ..put('/files/<ignored|.*>', _putFilesHandler)
      ..delete('/files/<ignored|.*>', _deleteFilesHandler)
      // Return 404 for everything else
      ..all('/<ignored|.*>', _notFoundHandler);

    var handler = Pipeline()
        .addMiddleware(logRequests(logger: _logger))
        .addMiddleware(_validateClock)
        .addHandler(router);

    var server = await io.serve(handler, '0.0.0.0', port);
    print('Listening on port ${server.port}…');
  }

  FutureOr<Response> _wsHandler(Request request) {
    var handler = webSocketHandler((webSocket) async {
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
      indexer.changes.listen((event) {
        webSocket.sink.add(jsonEncode([event]));
      });
    });

    return handler(request);
  }

  FutureOr<Response> _manifestHandler(Request request) =>
      Response.ok(indexer.toJson());

  Response _getFilesHandler(Request request) {
    final relativePath = Uri.decodeComponent(
        request.requestedUri.path.substring('/files'.length));
    final path = basePath + relativePath;
    if (!p.isWithin(basePath, path)) {
      return Response.forbidden('Path is outside of share directory');
    }

    final file = File(path);

    if (file.existsSync()) {
      final size = file.lengthSync();
      print('⬆  $relativePath (${size.asBytes})');
      return Response.ok(
        file.openRead(),
        headers: {
          HttpHeaders.contentLengthHeader: '$size',
        },
      );
    } else {
      return _notFoundHandler(request);
    }
  }

  Future<Response> _putFilesHandler(Request request) async {
    final relativePath = Uri.decodeComponent(
        request.requestedUri.path.substring('/files'.length));
    final path = basePath + relativePath;
    if (!p.isWithin(basePath, path)) {
      return Response.forbidden('Path is outside of share directory');
    }

    if (path.endsWith('/')) {
      Directory(path).createSync();
      return Response.ok('Created $relativePath');
    }

    final file = File('$path.reflect');
    file.parent.createSync(recursive: true);

    final size = int.parse(request.headers[HttpHeaders.contentLengthHeader]!);
    final indexed = DateTime.parse(request.headers['indexed']!);
    final modified = DateTime.parse(request.headers['modified']!);

    print('⬇  $relativePath (${size.asBytes})');
    final sink = file.openWrite();
    await sink.addStream(request.read());
    await sink.close();

    file.setLastModifiedSync(modified);
    file.renameSync(path);

    return Response.ok('Received $relativePath (${size.asBytes})');
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

    final relativePath = Uri.decodeComponent(
        request.requestedUri.path.substring('/files'.length));

    final path = basePath + relativePath;
    if (!p.isWithin(basePath, path)) {
      return Response.forbidden('Path is outside of share directory');
    }

    final local = indexer.get(path.md5);

    final entity =
        FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);

    print(local);
    if (entity.existsSync() &&
        ((local != null && indexed.isAfter(local.indexed)) || local == null)) {
      entity.deleteSync(recursive: true);
      await indexer.index();
    }

    return Response.ok('Deleted $relativePath');
  }

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

  void _logger(String message, bool isError) {
    if (isError) print('[ERROR]: $message');
  }
}

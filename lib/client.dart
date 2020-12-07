import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:reflect/indexer.dart';
import 'package:reflect/transfer.dart';
import 'package:web_socket_channel/io.dart';

import 'metadata.dart';

class Client {
  final Indexer indexer;
  final Uri address;
  final Transfer _transfer;

  var _connected = false;
  var _synchronizing = false;
  final remoteIndex = <String, Metadata>{};

  Client(this.indexer, this.address)
      : _transfer = Transfer(address);

  Future<void> connect() async {
    final url = address.replace(
      scheme: address.scheme == 'http' ? 'ws' : 'wss',
      path: '${address.path}/ws',
    );
    final channel = IOWebSocketChannel.connect(
      url,
      headers: {
        'clock': DateTime.now().toUtc().toIso8601String(),
      },
    );

    channel.stream.listen(
      (message) async {
        final index = (jsonDecode(message) as List)
            .cast<Map<String, dynamic>>()
            .map(Metadata.fromMap);
        for (final entry in index) {
          remoteIndex[entry.id] = entry;
        }
        _connected = true;
        await _mergeNext();
      },
      onDone: () {
        _connected = false;
        print('Disconnected');
      },
    );

    // Merge on local changes
    indexer.changes.listen((_) => _mergeNext());
  }

  Future<void> _mergeNext() async {
    if (!_connected || _synchronizing) return;
    _synchronizing = true;

    final remoteChanges = remoteIndex.values
        .where((e) => e.isNewer(indexer.get(e.id)))
        .toList()
      ..sort();

    final localChanges = indexer.values
        .where((e) => e.isNewer(remoteIndex[e.id]))
        .toList()
      ..sort();

    if (remoteChanges.isNotEmpty) {
      final entry = remoteChanges.first;
      if (entry.isDeleted) {
        if (entry.entity.existsSync()) {
          entry.entity.deleteSync(recursive: true);
        }
      } else {
        if (entry is FileMetadata) {
          await _transfer.download(entry);
        } else if (!entry.entity.existsSync()) {
          (entry.entity as Directory).createSync(recursive: true);
        }
      }
      // TODO Only index this file
      await indexer.index();
    } else if (localChanges.isNotEmpty) {
      final entry = localChanges.first;
      if (entry.isDeleted) {
        await _transfer.delete(entry);
      } else {
        if (entry is FileMetadata) {
          await _transfer.upload(entry);
        } else {
          await _transfer.createDir(entry as DirectoryMetadata);
        }
      }
      remoteIndex[entry.id] = entry;
    }

    _synchronizing = false;
    if (remoteChanges.isNotEmpty || localChanges.isNotEmpty) {
      // ignore: unawaited_futures
      _mergeNext();
    }
  }
}

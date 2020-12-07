import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import 'globals.dart';
import 'metadata.dart';
import 'util/extensions.dart';

typedef ChangeCallback = void Function(Metadata metadata);

const _indexDelay = 1;

class Indexer {
  final Box<Metadata> _manifest;

  Stream<Metadata> get changes =>
      _manifest.watch().map((e) => _manifest.get(e.key)!);

  Iterable<Metadata> get values => _manifest.values;

  Indexer._(this._manifest) {
    _monitor();
  }

  static Future<Indexer> open({int indexDelay = 1}) async {
    final home = Platform.environment['HOME'];
    final configPath = '$home/.reflect';
    final manifestFilename = basePath.md5;

    // Initialize Hive
    Hive.init('store');
    Hive.registerAdapter(MetadataAdapter(0));
    final local =
        await Hive.openBox<Metadata>(manifestFilename, path: configPath);

    print('Using manifest file ${local.path}');

    return Indexer._(local);
  }

  Metadata? get(String id) => _manifest.get(id);

  String toJson() => jsonEncode(_manifest.values.toList());

  Future<void> _monitor() async {
    while (true) {
      await _index();
      await Future.delayed(const Duration(seconds: _indexDelay));
    }
  }

  Future<void> index() => _index();

  Future<void> _index() async {
    // Load the state as last seen
    final localMap = _manifest.toMap()..removeWhere((_, e) => e.isDeleted);

    // Load the current state
    final entries = Directory(basePath)
        .listSync(recursive: true)
        .where((e) => !(e is File && e.path.endsWith('.reflect')));

    final entryPaths = entries.map((e) => e.relativePath(basePath)).toSet();
    // Look for deleted items
    for (final metadata
        in localMap.values.where((e) => !entryPaths.contains(e.relativePath))) {
      final newMetadata = metadata.asDeleted();
      // Mark as deleted in the local index
      await _manifest.put(newMetadata.relativePath.md5, newMetadata);
    }

    // Look for new and modified files
    for (final entry in entries) {
      final existing = localMap.remove(entry.relativePath(basePath).md5);
      if (existing == null || !existing.represents(entry)) {
        try {
          final metadata = entry is File
              ? await FileMetadata.fromFile(entry)
              : await DirectoryMetadata.fromDirectory(entry as Directory);
          // Make sure file wasn't deleted while computing its md5
          if (entry.existsSync()) {
            await _manifest.put(metadata.id, metadata);
          }
        } catch (e) {
          print(e);
        }
      }
    }
  }
}

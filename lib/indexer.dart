import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:xdg_directories/xdg_directories.dart';

import 'metadata.dart';
import 'util/extensions.dart';

class Indexer {
  final Directory _dir;
  late final Box<Metadata> _manifest;
  final _knownMd5s = <String>{};

  Future<Iterable<Metadata>>? _indexFuture;

  String get path => _dir.path;

  Iterable<Metadata> get values => _manifest.values;

  Indexer._(this._dir, this._manifest) {
    _knownMd5s.addAll(values
        .whereType<FileMetadata>()
        .where((e) => !e.isDeleted)
        .map((e) => e.md5!));
  }

  static Future<Indexer> open(String path) async {
    // Normalize path
    final dir = Directory(Directory(path).resolveSymbolicLinksSync());

    final configPath = '${configHome.path}/Reflect/manifests';
    final manifestFilename = dir.path.md5;

    // Initialize Hive
    Hive.init('store');
    Hive.registerAdapter(MetadataAdapter(0));
    final box =
        await Hive.openBox<Metadata>(manifestFilename, path: configPath);

    print('Using manifest file ${box.path}');

    return Indexer._(dir, box);
  }

  Directory getDirectory(DirectoryMetadata metadata) => metadata.entity(path);

  File getFile(FileMetadata metadata) => metadata.entity(path);

  Metadata? get(String path) => _manifest.get(path);

  Future<void> put(Metadata entry) => _manifest.put(entry.path, entry);

  String toJson() => jsonEncode(_manifest.values.toList());

  /// Checks the local filesystem for changes.
  /// If an index is already underway, it is returned instead of starting a new one.
  Future<Iterable<Metadata>> index() {
    _indexFuture ??= _index()..whenComplete(() => _indexFuture = null);
    return _indexFuture!;
  }

  /// Looks for an existing file with the same md5 and size
  File? getDuplicate(FileMetadata metadata) {
    // Quickly check if the md5 is known
    if (_knownMd5s.contains(metadata.md5)) {
      // Deep search for file metadata with the same md5
      try {
        return values
            .whereType<FileMetadata>()
            .firstWhere((m) => m.md5 == metadata.md5 && m.size == metadata.size)
            .entity(path);
      } catch (_) {}
    }
    return null;
  }

  Future<Iterable<Metadata>> _index() async {
    final changes = <Metadata>[];

    // Load the known state
    final state = _manifest.toMap()..removeWhere((_, e) => e.isDeleted);

    // List all entries, skip downloads in progress
    final entries = await _dir
        .list(recursive: true)
        .where((e) => !e.path.endsWith('.reflecting'))
        .toList();
    final entryPaths = entries.map((e) => e.relativePath(path)).toSet();

    // Look for deleted items
    for (final metadata
        in state.values.where((e) => !entryPaths.contains(e.path))) {
      final newMetadata = metadata.deleted();
      // Mark as deleted in the local state
      changes.add(newMetadata);
    }

    // Look for new and modified files
    for (final entry in entries) {
      final existing = state.remove(entry.relativePath(path));
      if (existing == null || !existing.represents(entry)) {
        final metadata = entry is File
            ? await FileMetadata.fromFile(path, entry)
            : await DirectoryMetadata.fromDirectory(path, entry as Directory);
        changes.add(metadata);
        print('🔎 $metadata');
      }
    }

    // Apply changes to manifest
    await _manifest.putAll({for (final c in changes) c.path: c});
    _knownMd5s.addAll(changes
        .whereType<FileMetadata>()
        .where((e) => !e.isDeleted)
        .map((e) => e.md5!));

    return changes;
  }

  Future<void> reset() => _manifest.clear();
}

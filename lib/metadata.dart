import 'dart:io';

import 'package:hive/hive.dart';

import 'util/extensions.dart';

sealed class Metadata implements Comparable<Metadata> {
  final String path;
  // When this entry was last changed in the file system
  final DateTime changed;
  final bool isDeleted;

  Metadata(this.path, DateTime changed, this.isDeleted)
      : changed = changed.normalize();

  static Metadata fromMap(Map<String, dynamic> map) {
    final path = map['path'];
    final changed = DateTime.parse(map['changed']);
    final isDeleted = map['is_deleted'];

    return map.containsKey('md5')
        ? FileMetadata(path, changed, DateTime.parse(map['modified']),
            map['size'], map['md5'], isDeleted)
        : DirectoryMetadata(path, changed, isDeleted);
  }

  /// Marks this entry as deleted.
  /// Because it's impossible to know the exact deletion time, the modified date
  /// is conservatively set to the last index time + 1ms.
  Metadata deleted();

  FileSystemEntity entity(String basePath);

  bool represents(FileSystemEntity entity);

  Map<String, dynamic> toJson() => {
        'path': path,
        'changed': changed.toIso8601String(),
        'is_deleted': isDeleted,
      };

  @override
  int compareTo(Metadata other) {
    // Sort directories before files
    if (runtimeType != other.runtimeType) {
      return this is DirectoryMetadata ? -1 : 1;
    }
    // Sort deleted fist
    if (isDeleted != other.isDeleted) {
      return isDeleted ? -1 : 1;
    }
    // Sort by path length if directory
    if (this is DirectoryMetadata) {
      return path.compareTo(other.path);
    }
    // Sort by size if file
    if (!isDeleted && this is FileMetadata) {
      return (this as FileMetadata)
          .size!
          .compareTo((other as FileMetadata).size!);
    }
    return 0;
  }

  bool isNewer(Metadata? other) =>
      other == null || this != other && (changed.isAfter(other.changed));
}

class DirectoryMetadata extends Metadata {
  DirectoryMetadata(super.path, super.indexed, super.isDeleted);

  static Future<DirectoryMetadata> fromDirectory(
          String basePath, Directory directory) async =>
      DirectoryMetadata(
        directory.relativePath(basePath),
        directory.statSync().changed,
        false,
      );

  @override
  DirectoryMetadata deleted() =>
      DirectoryMetadata(path, changed.increment(), true);

  @override
  Directory entity(String basePath) => Directory('$basePath/$path');

  @override
  bool represents(FileSystemEntity other) =>
      other is Directory && other.path.endsWith(path);

  @override
  bool operator ==(Object other) =>
      other is DirectoryMetadata &&
      path == other.path &&
      isDeleted == other.isDeleted;

  @override
  int get hashCode => Object.hash(path, isDeleted);

  @override
  String toString() => '${isDeleted ? '🗑️' : '📁'} $path/';
}

class FileMetadata extends Metadata {
  // Different from changed in that the modified time represents the data itself and survives file copies
  final DateTime modified;
  final int? size;
  final String? md5;

  FileMetadata(String path, DateTime changed, DateTime modified, this.size,
      this.md5, bool isDeleted)
      : modified = modified.normalize(),
        super(path, changed, isDeleted);

  static Future<FileMetadata> fromFile(String basePath, File file) async {
    final stat = file.statSync();
    return FileMetadata(
      file.relativePath(basePath),
      stat.changed,
      stat.modified,
      stat.size,
      await file.md5,
      false,
    );
  }

  @override
  FileMetadata deleted() =>
      FileMetadata(path, DateTime.now(), changed.increment(), null, null, true);

  @override
  File entity(String basePath) => File('$basePath/$path');

  @override
  bool represents(FileSystemEntity entity) =>
      entity is File &&
      entity.path.endsWith(path) &&
      entity.lastModifiedSync().normalize() == modified &&
      entity.lengthSync() == size;

  @override
  bool operator ==(other) =>
      other is FileMetadata &&
      path == other.path &&
      modified == other.modified &&
      isDeleted == other.isDeleted &&
      size == other.size &&
      md5 == other.md5;

  @override
  int get hashCode => Object.hash(path, isDeleted, size, md5);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'modified': modified.toIso8601String(),
        'size': size,
        'md5': md5,
      };

  @override
  String toString() => isDeleted ? '🗑️ $path' : '📄 $path (${size!.asBytes})';
}

class MetadataAdapter extends TypeAdapter<Metadata> {
  @override
  final int typeId;

  MetadataAdapter(this.typeId);

  @override
  void write(BinaryWriter writer, Metadata obj) {
    writer.writeMap(obj.toJson());
  }

  @override
  Metadata read(BinaryReader reader) =>
      Metadata.fromMap(reader.readMap().cast<String, dynamic>());
}

import 'dart:io';

import 'package:hive/hive.dart';

import 'globals.dart';
import 'util/extensions.dart';

class DirectoryMetadata extends Metadata {
  @override
  Directory get entity => Directory('$basePath/$relativePath');

  DirectoryMetadata(
      String id, String relativePath, DateTime indexed, bool isDeleted)
      : super(id, relativePath, indexed, isDeleted);

  static Future<DirectoryMetadata> fromDirectory(Directory directory) async =>
      DirectoryMetadata(
        directory.relativePath(basePath).md5,
        directory.relativePath(basePath),
        DateTime.now(),
        false,
      );

  @override
  DirectoryMetadata asDeleted() =>
      DirectoryMetadata(id, relativePath, DateTime.now(), true);

  @override
  bool represents(FileSystemEntity other) =>
      other is Directory && other.path.endsWith(relativePath);

  @override
  bool operator ==(Object other) =>
      other is DirectoryMetadata &&
      relativePath == other.relativePath &&
      isDeleted == other.isDeleted;

  @override
  int get hashCode => Object.hash(relativePath, isDeleted);

  @override
  String toString() => '${isDeleted ? '🗑️' : '📁'} $relativePath/';
}

class FileMetadata extends Metadata {
  final DateTime modified;
  final int? size;
  final String? md5;

  @override
  File get entity => File('$basePath/$relativePath');

  FileMetadata(String id, String relativePath, DateTime indexed,
      DateTime modified, this.size, this.md5, bool isDeleted)
      : modified = modified.toUtc(),
        super(id, relativePath, indexed, isDeleted);

  static Future<FileMetadata> fromFile(File file) async => FileMetadata(
        file.relativePath(basePath).md5,
        file.relativePath(basePath),
        DateTime.now(),
        file.lastModifiedSync(),
        file.lengthSync(),
        await file.md5,
        false,
      );

  @override
  FileMetadata asDeleted() => FileMetadata(
      id, relativePath, DateTime.now(), modified, null, null, true);

  @override
  bool represents(FileSystemEntity other) =>
      other is File &&
      other.path.endsWith(relativePath) &&
      other.lastModifiedSync().toUtc() == modified &&
      other.lengthSync() == size;

  @override
  bool operator ==(other) =>
      other is FileMetadata &&
      relativePath == other.relativePath &&
      isDeleted == other.isDeleted &&
      size == other.size &&
      md5 == other.md5;

  @override
  int get hashCode => Object.hash(relativePath, isDeleted, size, md5);

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'modified': modified.toIso8601String(),
        'size': size,
        'md5': md5,
      };

  @override
  String toString() =>
      isDeleted ? '🗑️ $relativePath' : '📄 $relativePath (${size!.asBytes})';
}

abstract class Metadata extends Comparable<Metadata> {
  final String id;
  final String relativePath;
  final DateTime indexed;
  final bool isDeleted;

  FileSystemEntity get entity;

  Metadata(this.id, this.relativePath, DateTime indexed, this.isDeleted)
      : indexed = indexed.toUtc();

  static Metadata fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final relativePath = map['relative_path'];
    final indexed = DateTime.parse(map['indexed']);
    final isDeleted = map['is_deleted'];

    return map.containsKey('md5')
        ? FileMetadata(id, relativePath, indexed,
            DateTime.parse(map['modified']), map['size'], map['md5'], isDeleted)
        : DirectoryMetadata(id, relativePath, indexed, isDeleted);
  }

  Metadata asDeleted();

  bool represents(FileSystemEntity other);

  Map<String, dynamic> toJson() => {
        'id': id,
        'relative_path': relativePath,
        'indexed': indexed.toIso8601String(),
        'is_deleted': isDeleted,
      };

  @override
  int compareTo(Metadata other) {
    // Sort files before directories
    if (runtimeType != other.runtimeType) {
      return this is FileMetadata ? -1 : 1;
    }
    // Sort undeleted files fist
    if (isDeleted != other.isDeleted) {
      return isDeleted ? 1 : -1;
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
      other == null || this != other && indexed.isAfter(other.indexed);
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

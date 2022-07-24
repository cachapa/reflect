import 'dart:io';

import 'package:reflect/metadata.dart';
import 'package:test/test.dart';

void main() {
  final basePath = 'test/sandbox';
  final now = DateTime.now().toUtc();
  final modified = File('$basePath/a.txt').lastModifiedSync().toUtc();

  final aMetadata = FileMetadata(
    'a.txt',
    now,
    modified,
    14,
    'd23946cf1fd5d58880ea7a1dd5b5ac9d',
    false,
  );

  test('Base constructor', () {
    expect(aMetadata.path, 'a.txt');
    expect(aMetadata.size, 14);
    expect(aMetadata.modified, modified);
    expect(aMetadata.md5, 'd23946cf1fd5d58880ea7a1dd5b5ac9d');
  });

  test('fromFile', () async {
    final metadata =
        await FileMetadata.fromFile(basePath, File('test/sandbox/a.txt'));
    expect(metadata, aMetadata);
    final copyMetadata =
        FileMetadata.fromFile(basePath, File('test/sandbox/a_copy.txt'));
    expect(copyMetadata, isNot(aMetadata));
  });

  test('file', () {
    final file = aMetadata.entity(basePath);
    expect(file.existsSync(), true);
  });

  test('fromMap', () {
    expect(
        Metadata.fromMap({
          'relative_path': 'a.txt',
          'indexed': now.toIso8601String(),
          'modified': modified.toIso8601String(),
          'size': 14,
          'md5': 'd23946cf1fd5d58880ea7a1dd5b5ac9d',
          'is_deleted': false,
        }),
        aMetadata);
    final metadata = Metadata.fromMap({
      'relative_path': 'b.txt',
      'indexed': now.toIso8601String(),
      'modified': modified.toIso8601String(),
      'size': null,
      'md5': null,
      'is_deleted': true,
    });
    expect(metadata.isDeleted, true);
  });

  test('toJson', () {
    expect(aMetadata.toJson(), {
      'relative_path': 'a.txt',
      'indexed': now.toIso8601String(),
      'modified': modified.toIso8601String(),
      'size': 14,
      'md5': 'd23946cf1fd5d58880ea7a1dd5b5ac9d',
      'is_deleted': false,
    });
    expect(aMetadata.deleted().toJson()['is_deleted'], true);
  });

  test('isSameAs', () {
    expect(aMetadata.represents(File('test/sandbox/a.txt')), true);
    expect(aMetadata.represents(File('test/sandbox/a_copy.txt')), false);
  });

  test('deleted', () {
    expect(aMetadata.isDeleted, false);
    final metadata = aMetadata.deleted();
    expect(metadata.isDeleted, true);
  });
}

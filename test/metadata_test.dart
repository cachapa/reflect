import 'dart:convert';
import 'dart:io';

import 'package:reflect/globals.dart';
import 'package:reflect/metadata.dart';
import 'package:test/test.dart';

void main() {
  basePath = 'test/sandbox';

  final now = DateTime.now().toUtc();
  final modified = File('test/sandbox/a.txt').lastModifiedSync().toUtc();

  final aMetadata = FileMetadata(
    'a5e54d1fd7bb69a228ef0dcd2431367e',
    'a.txt',
    now,
    modified,
    14,
    'd23946cf1fd5d58880ea7a1dd5b5ac9d',
    false,
  );

  test('Base constructor', () {
    expect(aMetadata.id, 'a5e54d1fd7bb69a228ef0dcd2431367e');
    expect(aMetadata.relativePath, 'a.txt');
    expect(aMetadata.size, 14);
    expect(aMetadata.modified, modified);
    expect(aMetadata.md5, 'd23946cf1fd5d58880ea7a1dd5b5ac9d');
  });

  test('fromFile', () async {
    final metadata = await FileMetadata.fromFile(File('test/sandbox/a.txt'));
    expect(metadata, aMetadata);
    final copyMetadata = FileMetadata.fromFile(File('test/sandbox/a_copy.txt'));
    expect(copyMetadata, isNot(aMetadata));
  });

  test('file', () {
    final file = aMetadata.entity;
    expect(file.existsSync(), true);
  });

  test('fromMap', () {
    expect(
        Metadata.fromMap({
          'id': 'a5e54d1fd7bb69a228ef0dcd2431367e',
          'relative_path': 'a.txt',
          'indexed': now.toIso8601String(),
          'modified': modified.toIso8601String(),
          'size': 14,
          'md5': 'd23946cf1fd5d58880ea7a1dd5b5ac9d',
          'is_deleted': false,
        }),
        aMetadata);
    final metadata = Metadata.fromMap({
      'id': 'abc',
      'relative_path': 'a.txt',
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
      'id': 'a5e54d1fd7bb69a228ef0dcd2431367e',
      'relative_path': 'a.txt',
      'indexed': now.toIso8601String(),
      'modified': modified.toIso8601String(),
      'size': 14,
      'md5': 'd23946cf1fd5d58880ea7a1dd5b5ac9d',
      'is_deleted': false,
    });
    expect(aMetadata.asDeleted().toJson()['is_deleted'], true);
  });

  test('isSameAs', () {
    expect(aMetadata.represents(File('test/sandbox/a.txt')), true);
    expect(aMetadata.represents(File('test/sandbox/a_copy.txt')), false);
  });

  test('deleted', () {
    expect(aMetadata.isDeleted, false);
    final metadata = aMetadata.asDeleted();
    expect(metadata.isDeleted, true);
  });
}

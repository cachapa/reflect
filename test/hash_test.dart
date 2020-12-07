import 'dart:io';

import 'package:reflect/util/hash.dart';
import 'package:test/test.dart';

final testFilePath = 'test/sandbox/a.txt';

void main() {
  test('md5sum check', () {
    expect(Hash.isSystemMd5Available, true);
  });

  test('hash string', () {
    expect(Hash.md5String('test string'), '6f8db599de986fab7a21625b7916589c');
  });

  test('hash file', () async {
    final file = File(testFilePath);
    expect(await Hash.md5File(file), 'd23946cf1fd5d58880ea7a1dd5b5ac9d');
  });

  test('system hash', () async {
    expect(await Hash.systemMd5(testFilePath), 'd23946cf1fd5d58880ea7a1dd5b5ac9d');
  });

  test('native hash', () async {
    final file = File(testFilePath);
    expect(await Hash.nativeMd5(file), 'd23946cf1fd5d58880ea7a1dd5b5ac9d');
  });
}

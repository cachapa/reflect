import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

class Hash {
  // Dart's MD5 hash is about 10x slower than the command line
  // https://github.com/dart-lang/crypto/issues/5
  static bool isSystemMd5Available = () {
    try {
      Process.runSync('md5sum', ['--version']);
      return true;
    } catch (e) {
      return false;
    }
  }();

  Hash._();

  static FutureOr<String> md5File(File file) async =>
      isSystemMd5Available ? systemMd5(file.path) : await nativeMd5(file);

  static String md5String(String string) =>
      md5.convert(string.codeUnits).toString();

  static String systemMd5(String path) =>
      Process.runSync('md5sum', [path]).stdout.toString().substring(0, 32);

  static Future<String> nativeMd5(File file) async =>
      (await md5.bind(file.openRead()).first).toString();
}

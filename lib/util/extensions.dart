import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:reflect/util/hash.dart';

extension FileSystemEntityX on FileSystemEntity {
  String relativePath(String basePath) => p.relative(path, from: basePath);
}

extension FileExtensions on File {
  FutureOr<String> get md5 => Hash.md5File(this);
}

extension StringExtensions on String {
  String get base64 => base64Encode(utf8.encode(this));

  String get md5 => Hash.md5String(this);

  String fullPath(String basePath) => '$basePath/$this';
}

extension IntExtensions on int {
  static const byteSuffixes = [
    'B',
    'KB',
    'MB',
    'GB',
    'TB',
    'PB',
    'EB',
    'ZB',
    'YB',
  ];

  String get asBytes {
    if (this < 1024) return '$this B';
    final i = (log(this) / log(1024)).floor();
    return ((this / pow(1024, i)).toStringAsFixed(1)) + ' ' + byteSuffixes[i];
  }
}

extension DoubleExtensions on double {
  String get asPercentage => '${(this * 100).toStringAsFixed(1)}%';
}

extension DateTimeExtension on DateTime {
  DateTime normalize() => toUtc().copyWith(millisecond: 0, microsecond: 0);

  DateTime increment() => add(Duration(milliseconds: 1));
}

extension MapX on Map {
  String toJson() => jsonEncode(this);
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:reflect/client.dart';
import 'package:reflect/globals.dart';
import 'package:reflect/indexer.dart';
import 'package:reflect/server.dart';
import 'package:reflect/util/random_id.dart';

const _defaultPort = 8123;

final parser = ArgParser();

String get usage => '''Usage: reflect PATH [OPTION]...

Options:\n${parser.usage}''';

Future<void> main(List<String> arguments) async {
  parser
    ..addFlag(
      'server',
      abbr: 's',
      help: 'Listen to incoming connections.',
      negatable: false,
    )
    ..addOption(
      'port',
      abbr: 'p',
      help: 'Specify server port',
    )
    ..addOption(
      'connect',
      abbr: 'c',
      help: 'Connect to the specified server address',
    )
    // TODO Option to specify manifest filename
    // TODO Option to specify max clock drift
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Print this usage information.',
      negatable: false,
      callback: (_) => usage,
    );

  final results = parser.parse(arguments);

  if (results.command != null) {
    print(generateRandomId());
    exit(0);
  }

  if (results.rest.length != 1) {
    fail('missing arguments');
  }

  basePath = results.rest[0];
  final server = results['server'];
  final port = int.tryParse(results['port'] ?? '');
  final connect = results['connect'];

  if (server == false && connect == null) {
    print('Error: one of -s or -c options required');
    exit(0);
  }

  if (server == false && port != null) {
    print('Warning: specifying the port only works for the server.\nUse the format http(s)://address:port to connect to a non-standard port.');
  }

  final dir = Directory(basePath);
  if (!dir.existsSync()) {
    print('Path not found or is not a directory: $basePath');
    exit(0);
  }

  late final Uri address;
  if (connect != null) {
    if ((connect as String).contains('://')) {
      address = Uri.parse(connect);
      if (!{'http', 'https'}.contains(address.scheme)) {
        print('Unknown protocol: ${address.scheme}');
        exit(0);
      }
    } else {
      address = Uri.parse('http://$connect');
    }
  }

  final indexer = await Indexer.open();
  indexer.changes.listen((e) => print('🔎 $e'));
  await indexer.index();

  await Future.wait([
    if (server) Server(indexer, port ?? _defaultPort).serve(),
    if (connect != null) Client(indexer, address).connect(),
  ]);
}

void fail(String message) {
  print('reflect: $message\n\n$usage');
  exit(64);
}

import 'dart:io';

import 'package:args/args.dart';
import 'package:reflect/client.dart';
import 'package:reflect/indexer.dart';
import 'package:reflect/server.dart';

const _defaultPort = 8123;

final parser = ArgParser();

String get usage => '''Usage: reflect COMMAND [OPTION]... DIRECTORY

Options:\n${parser.usage}''';

Future<void> main(List<String> arguments) async {
  parser
    ..addCommand(
      'index',
      ArgParser()
        ..addFlag('reset',
            abbr: 'r', help: 'Reset manifest.', negatable: false),
    )
    ..addCommand(
      'serve',
      ArgParser()
        ..addOption(
          'port',
          abbr: 'p',
          help: 'Server port (default: 8008)',
        ),
    )
    ..addCommand(
      'connect',
    )
    // ..addFlag(
    //   'server',
    //   abbr: 's',
    //   help: 'Listen to incoming connections.',
    //   negatable: false,
    // )
    // ..addOption(
    //   'port',
    //   abbr: 'p',
    //   help: 'Specify server port',
    // )
    // ..addOption(
    //   'connect',
    //   abbr: 'c',
    //   help: 'Connect to the specified server address',
    // )
    // ..addOption(
    //   'authorization',
    //   abbr: 'a',
    //   help: 'Supply basic auth credentials',
    // )
    // // TODO Option to specify manifest filename
    // // TODO Option to specify max clock drift
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Print this usage information.',
      negatable: false,
      callback: (_) => usage,
    );

  final results = parser.parse(arguments);

  switch (results.command?.name) {
    case 'index':
      await index(results.command!.arguments.first,
          reset: results.command!.wasParsed('reset'));
      exit(0);
    case 'serve':
      await serve(results.command!.arguments.first,
          int.parse(results.command!.option('port') ?? '8008'));
      exit(0);
    case 'connect':
      await connect(
          results.command!.arguments.first, results.command!.arguments.last);
      exit(0);
    default:
      if (results.wasParsed('help')) {
        print(usage);
        exit(0);
      }
      fail('wrong or missing arguments');
  }

  // Capture help

  // Parse command
  // if (results.command == null) {
  //   fail('missing arguments');
  // }

  // basePath = results.rest[0];
  // final server = results['server'];
  // final port = int.tryParse(results['port'] ?? '');
  // final connect = results['connect'];
  // final authorization = results['authorization'] as String?;

  // if (server == false && connect == null) {
  //   print('Error: one of -s or -c options required');
  //   exit(0);
  // }
  //
  // if (server == false && port != null) {
  //   print(
  //       'Warning: specifying the port only works for the server.\nUse the format http(s)://address:port to connect to a non-standard port.');
  // }
  //
  // if (connect == null && authorization != null) {
  //   print('Warning: authorization only works when connecting to a server.');
  // }
  //
  // if (authorization != null && !authorization.contains(':')) {
  //   print('Invalid authorization string. Use the format username:password');
  //   exit(0);
  // }

  // final dir = Directory(basePath);
  // if (!dir.existsSync()) {
  //   print('Path not found or is not a directory: $basePath');
  //   exit(0);
  // }

  // late final Uri address;
  // if (connect != null) {
  //   if ((connect as String).contains('://')) {
  //     address = Uri.parse(connect);
  //     if (!{'http', 'https'}.contains(address.scheme)) {
  //       print('Unknown protocol: ${address.scheme}');
  //       exit(0);
  //     }
  //   } else {
  //     address = Uri.parse('http://$connect');
  //   }
  // }

  // final indexer = await Indexer.open();
  // indexer.changes.listen((e) => print('🔎 $e'));

  // await Future.wait([
  //   if (server) Server(indexer, port ?? _defaultPort).serve(),
  //   if (connect != null) Client(indexer, address, authorization).connect(),
  // ]);
}

Future<void> connect(String address, String path) async {
  print('Indexing…');
  final indexer = await Indexer.open(path);
  await indexer.index();
  await Client(indexer, address).sync();
}

Future<void> serve(String path, int port) async {
  print('Indexing…');
  final indexer = await Indexer.open(path);
  await indexer.index();
  await Server(indexer, port).serve();
}

Future<void> index(String path, {bool reset = false}) async {
  final indexer = await Indexer.open(path);
  if (reset) {
    print('Resetting manifest…');
    await indexer.reset();
  }
  print('Indexing…');
  final changes = await indexer.index();
  print(
      '${changes.where((e) => !e.isDeleted).length} changes, ${changes.where((e) => e.isDeleted).length} deletions detected.');
}

void fail(String message) {
  print('reflect: $message\n\n$usage');
  exit(64);
}

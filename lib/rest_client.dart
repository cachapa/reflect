import 'dart:io';

import 'package:http/http.dart';
import 'package:reflect/util/extensions.dart';

class RestClient extends BaseClient {
  final String? credentials;
  final client = Client();

  RestClient(this.credentials);

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers.addAll({
      if (credentials != null)
        HttpHeaders.authorizationHeader: 'Basic ${credentials!.base64}',
      'clock': DateTime.now().toUtc().toIso8601String(),
    });
    return client.send(request);
  }
}

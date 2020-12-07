import 'package:http/http.dart';

class RestClient extends BaseClient {
  final client = Client();

  RestClient();

  @override
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers.addAll({
      'clock': DateTime.now().toUtc().toIso8601String(),
    });
    return client.send(request);
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guitarbar/core/vision/vision_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const cfg = (
    baseUrl: 'https://api.example.com/v4/',
    apiKey: 'sk-test',
    model: 'glm-4v-flash',
  );

  test('成功：取 choices[0].message.content；请求体含 data URI 图', () async {
    http.Request? captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': '{"measures": []}'}}
            ]
          }),
          200);
    });
    final c = VisionClient(client: client);
    final out = await c.complete(
        baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
        prompt: 'p', png: Uint8List.fromList([1, 2, 3]));
    expect(out, '{"measures": []}');
    final body = jsonDecode(captured!.body);
    expect(captured!.url.toString(), 'https://api.example.com/v4/chat/completions');
    expect(captured!.headers['Authorization'], 'Bearer sk-test');
    final content = body['messages'][0]['content'] as List;
    expect(content[1]['image_url']['url'], startsWith('data:image/png;base64,'));
  });

  test('HTTP 401 → VisionException', () async {
    final c = VisionClient(
        client: MockClient((req) async => http.Response('denied', 401)));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()));
  });

  test('响应缺 content → VisionException', () async {
    final c = VisionClient(
        client: MockClient((req) async =>
            http.Response(jsonEncode({'choices': []}), 200)));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()));
  });
}

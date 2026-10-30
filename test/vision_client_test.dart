import 'dart:async';
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
    // 默认不传 thinking（OpenAI 严格端点未知参数会 400）。
    expect(body.containsKey('thinking'), isFalse);
  });

  test('disableThinking=true：请求体带 thinking disabled；maxTokens 可调', () async {
    http.Request? captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'ok'}}
            ]
          }),
          200);
    });
    final c = VisionClient(
        client: client, maxTokens: 8192, disableThinking: true);
    final out = await c.complete(
        baseUrl: cfg.baseUrl, apiKey: cfg.apiKey, model: cfg.model,
        prompt: 'p', png: Uint8List.fromList([1, 2, 3]));
    expect(out, 'ok');
    final body = jsonDecode(captured!.body);
    expect(body['thinking'], {'type': 'disabled'});
    expect(body['max_tokens'], 8192);
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

  test('坏 JSON → VisionException', () async {
    final c = VisionClient(
        client: MockClient((req) async => http.Response('not json', 200)));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()));
  });

  test('无尾斜杠 baseUrl 拼接同样正确', () async {
    http.Request? captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'ok'}}
            ]
          }),
          200);
    });
    final c = VisionClient(client: client);
    final out = await c.complete(
        baseUrl: 'https://api.example.com/v4', apiKey: cfg.apiKey,
        model: cfg.model, prompt: 'p', png: Uint8List.fromList([1]));
    expect(out, 'ok');
    expect(captured!.url.toString(),
        'https://api.example.com/v4/chat/completions');
  });

  test('超时 → VisionException 且消息含"超时"', () async {
    final c = VisionClient(
        client: MockClient((req) async {
          await Completer<void>().future; // 永不完成，模拟服务端不回包
          return http.Response('', 200);
        }),
        timeout: const Duration(milliseconds: 50));
    expect(
        () => c.complete(baseUrl: cfg.baseUrl, apiKey: cfg.apiKey,
            model: cfg.model, prompt: 'p',
            png: Uint8List.fromList([1])),
        throwsA(isA<VisionException>()
            .having((e) => e.message, 'message', contains('超时'))));
  });
}

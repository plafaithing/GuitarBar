import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// OpenAI 兼容 chat-completions 视觉请求（设计文档 §5.2）。
/// 一个协议覆盖智谱/OpenAI/DeepSeek/硅基流动/Ollama 等，不绑定厂商。
class VisionException implements Exception {
  const VisionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VisionClient {
  VisionClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<String> complete({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
    required Uint8List png,
    String mime = 'image/png',
  }) async {
    // 统一去掉末尾斜杠再拼路径，兼容 baseUrl 带/不带尾斜杠。
    final b = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$b/chat/completions');
    final body = jsonEncode({
      'model': model,
      'temperature': 0.1,
      'max_tokens': 8192,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mime;base64,${base64Encode(png)}'}
            },
          ],
        },
      ],
    });
    final http.Response res;
    try {
      res = await _client.post(uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: body);
    } catch (e) {
      throw VisionException('网络请求失败：$e');
    }
    if (res.statusCode != 200) {
      throw VisionException('HTTP ${res.statusCode}：${res.body}');
    }
    return _extractContent(res.body);
  }

  /// 从响应体取 choices[0].message.content。
  /// 外部响应结构不可信：任何结构异常都归入"响应缺少 content"，不裸抛 TypeError。
  String _extractContent(String responseBody) {
    final dynamic data;
    try {
      data = jsonDecode(responseBody);
    } on FormatException catch (e) {
      throw VisionException('响应不是合法 JSON：$e');
    }
    String? content;
    if (data is Map) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map) {
            final c = message['content'];
            if (c is String) content = c;
          }
        }
      }
    }
    if (content == null || content.isEmpty) {
      throw const VisionException('响应缺少 content');
    }
    return content;
  }
}

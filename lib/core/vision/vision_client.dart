import 'dart:async';
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
  VisionClient({http.Client? client,
      this.timeout = const Duration(seconds: 120),
      this.maxTokens = 1024,
      this.disableThinking = false})
      : _client = client ?? http.Client();
  final http.Client _client;

  /// 单次请求超时；http 包无默认超时，须显式兜底。
  final Duration timeout;

  /// 输出 token 上限。默认 1024 取各端点最小公分母（2026-10-30 用户实测：
  /// glm-4v-flash 上限即 1024，传 8192 直接 HTTP 400 code 1210）。
  /// 整页识谱输出大——换用上限更高的模型（如 glm-4.5v）时可在构造处调大。
  final int maxTokens;

  /// 关闭思考模式（智谱 thinking 参数）。glm-4.5v 等思考模型识谱时会把
  /// max_tokens 全烧在 reasoning_content（content 为空、finish=length，
  /// 2026-10-30 探针实证）；识谱是结构化转换任务不需要推理。默认 false：
  /// OpenAI 等严格端点对未知参数报 400，仅智谱系场景按需开启。
  final bool disableThinking;

  /// 请求结束后由调用方视需要释放底层连接。
  void close() => _client.close();

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
    // baseUrl 是用户手输，解析失败同样落进 VisionException，不裸抛 FormatException。
    final Uri uri;
    try {
      uri = Uri.parse('$b/chat/completions');
    } on FormatException catch (e) {
      throw VisionException('baseUrl 无效：$e');
    }
    final body = jsonEncode({
      'model': model,
      'temperature': 0.1,
      'max_tokens': maxTokens,
      if (disableThinking) 'thinking': const {'type': 'disabled'},
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
          body: body).timeout(timeout);
    } on TimeoutException catch (_) {
      // 不兜底的话服务端不回包时 Future 永不完成，调用方永久卡死。
      throw VisionException(
          '请求超时（${timeout.inSeconds} 秒），请检查网络或稍后重试');
    } on Exception catch (e) {
      // 只接 Exception：编程错误（Error）保持响亮，不吞。
      throw VisionException('网络请求失败：$e');
    }
    // http 的 res.body 无 charset 时按 latin1 解码，中文错误体会乱码；
    // 显式按 utf8 解码，allowMalformed 容忍坏字节不抛。
    final bodyText = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode != 200) {
      throw VisionException('HTTP ${res.statusCode}：${_truncate(bodyText)}');
    }
    return _extractContent(bodyText);
  }

  /// 错误消息里的响应体截 200 字符，防网关/Cloudflare HTML 大页塞满提示。
  String _truncate(String s) =>
      s.length <= 200 ? s : '${s.substring(0, 200)}…';

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

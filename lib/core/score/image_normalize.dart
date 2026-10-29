import 'dart:typed_data';

import 'package:image/image.dart' as imgpkg;

/// 图片规范化：长边 ≤ maxSide 等比缩到 PNG（识别输入与页图统一格式）。
/// 解码失败抛 FormatException。
Future<Uint8List> normalizeImage(Uint8List bytes, {int maxSide = 4096}) async {
  imgpkg.Image? decoded;
  try {
    decoded = imgpkg.decodeImage(bytes);
  } catch (_) {
    // 部分解码器对垃圾输入不返回 null 而是直接抛异常（如 GifDecoder
    // isValidFile 越界读），在胶水层统一转成 FormatException。
    throw const FormatException('无法解码图片');
  }
  if (decoded == null) throw const FormatException('无法解码图片');
  if (decoded.width <= maxSide && decoded.height <= maxSide) return bytes;
  final w = decoded.width >= decoded.height
      ? maxSide
      : (decoded.width * maxSide / decoded.height).round();
  final h = decoded.height > decoded.width
      ? maxSide
      : (decoded.height * maxSide / decoded.width).round();
  final resized = imgpkg.copyResize(decoded, width: w, height: h);
  return Uint8List.fromList(imgpkg.encodePng(resized));
}

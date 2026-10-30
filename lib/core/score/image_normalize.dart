import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as imgpkg;

/// 图片规范化：解码后统一输出 PNG——长边 ≤ maxSide 保持原尺寸，否则等比
/// 缩到上限；识别输入与页图共用同一格式通道。解码失败抛 FormatException。
Future<Uint8List> normalizeImage(Uint8List bytes, {int maxSide = 4096}) {
  // 解码/缩放/编码全同步移入后台 isolate（同 pdf_raster 规矩）：手机照片
  // 单张解码即秒级，跑在 UI isolate 会整页冻结。闭包只捕获纯数据
  // （bytes/maxSide），typed data 发送即拷贝，不持任何原生资源句柄。
  return Isolate.run(() {
    imgpkg.Image? decoded;
    try {
      decoded = imgpkg.decodeImage(bytes);
    } catch (e) {
      // 部分解码器对垃圾输入不返回 null 而是直接抛异常（如 GifDecoder
      // isValidFile 越界读），在胶水层统一转成 FormatException。
      throw FormatException('无法解码图片：$e');
    }
    if (decoded == null) throw const FormatException('无法解码图片');
    // 始终输出 PNG：不透传原始字节，避免 JPEG 内容顶着 .png 文件名/mime 传播。
    if (decoded.width <= maxSide && decoded.height <= maxSide) {
      return Uint8List.fromList(imgpkg.encodePng(decoded));
    }
    final w = decoded.width >= decoded.height
        ? maxSide
        : (decoded.width * maxSide / decoded.height).round();
    final h = decoded.height > decoded.width
        ? maxSide
        : (decoded.height * maxSide / decoded.width).round();
    final resized = imgpkg.copyResize(decoded, width: w, height: h);
    return Uint8List.fromList(imgpkg.encodePng(resized));
  });
}

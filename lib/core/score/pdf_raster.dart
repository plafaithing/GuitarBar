import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as imgpkg;
import 'package:pdfrx/pdfrx.dart';

/// PDF → 逐页 PNG（默认 200 DPI，白底）。
/// 注意：pdfrx 2.x（pdfrx_engine 0.8.0）的 [PdfPage.render] 返回 PdfImage
/// （BGRA8888 原始像素，无 PNG 编码参数），此处用 package:image 转 PNG 编码。
class PdfRasterizer {
  const PdfRasterizer({this.dpi = 200});
  final double dpi;

  Future<List<Uint8List>> renderPages(File pdf) async {
    final doc = await PdfDocument.openFile(pdf.path);
    try {
      final scale = dpi / 72;
      final out = <Uint8List>[];
      for (final page in doc.pages) {
        // 省略 x/y/width/height 时按 fullWidth/fullHeight 渲染整页；
        // backgroundColor 为 AARRGGBB 整数（默认即白，显式表达白底语义）。
        final img = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          backgroundColor: 0xFFFFFFFF, // 白底：扫描件透明区识别更稳
        );
        if (img == null) {
          throw StateError('PDF 第 ${page.pageNumber} 页渲染失败');
        }
        try {
          // 像素→PNG 编码移入后台 isolate：A4@200DPI 约 15.5MB 像素拷贝，
          // 同步编码会冻结 UI isolate。闭包只捕获纯数据（pixels/宽高），
          // 不捕获 img（原生资源句柄不可跨 isolate）；typed data 发送即拷贝，
          // Isolate.run 返回后才 dispose，顺序安全。
          final pixels = img.pixels;
          final w = img.width;
          final h = img.height;
          final png = await Isolate.run(() {
            final decoded = imgpkg.Image.fromBytes(
              width: w,
              height: h,
              bytes: pixels.buffer,
              bytesOffset: pixels.offsetInBytes,
              numChannels: 4,
              order: imgpkg.ChannelOrder.bgra, // 引擎输出 BGRA 像素
            );
            return imgpkg.encodePng(decoded); // 返回类型即 Uint8List
          });
          out.add(png);
        } finally {
          img.dispose(); // PdfImage 持有原生资源，用完必须释放
        }
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }
}

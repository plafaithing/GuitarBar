import 'dart:io';
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
          final decoded = imgpkg.Image.fromBytes(
            width: img.width,
            height: img.height,
            bytes: img.pixels.buffer,
            bytesOffset: img.pixels.offsetInBytes,
            numChannels: 4,
            order: imgpkg.ChannelOrder.bgra, // 引擎输出 BGRA 像素
          );
          out.add(Uint8List.fromList(imgpkg.encodePng(decoded)));
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

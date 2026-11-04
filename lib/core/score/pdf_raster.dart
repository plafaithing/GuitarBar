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

  Future<List<Uint8List>> renderPages(File pdf) {
    // 整个"打开 + 逐页渲染"挪进后台 isolate（2026-11-03 用户实测批量导入
    // "点击导入卡死"）：page.render 是 pdfium FFI **同步**调用，几十页 ×
    // 每页数百 ms 全部冻结主 isolate——旧单文件导入"时间长"与本轮批量
    // "卡死"同根因，批量把它放大成不可用。闭包只捕获纯数据（path/dpi）；
    // pdfrx/pdfium 全链路纯 FFI（DynamicLibrary.process 取本进程已加载的
    // pdfium.dll，无平台通道），后台 isolate 安全；原生资源（doc/img）在
    // 后台 isolate 内创建并释放，不跨 isolate 传句柄。
    final path = pdf.path;
    final dpi = this.dpi;
    return Isolate.run(() async {
      final doc = await PdfDocument.openFile(path);
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
            // 像素→PNG 编码同样在后台 isolate 内同步做（本就在后台）。
            final pixels = img.pixels;
            final w = img.width;
            final h = img.height;
            final png = imgpkg.encodePng(imgpkg.Image.fromBytes(
                width: w,
                height: h,
                bytes: pixels.buffer,
                bytesOffset: pixels.offsetInBytes,
                numChannels: 4,
                order: imgpkg.ChannelOrder.bgra)); // 引擎输出 BGRA 像素
            out.add(png);
          } finally {
            img.dispose(); // PdfImage 持有原生资源，用完必须释放
          }
        }
        return out;
      } finally {
        await doc.dispose();
      }
    });
  }
}

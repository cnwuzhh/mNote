import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'package:saber/mnote/ink/ink_document.dart';
import 'package:saber/mnote/ink/ink_paint.dart';
import 'package:saber/mnote/model/models.dart';
import 'package:saber/mnote/reader/pdf_geometry.dart';

/// Exports [document] with excerpt highlights and handwriting as a new,
/// flattened PDF: every page is rendered to an image ([scale] pixels per PDF
/// point; 2.0 ≈ 144 dpi) with highlights and ink drawn on top, JPEG-encoded
/// and placed on a page of the original size. Text is not selectable in the
/// result; the original file is not modified.
Future<Uint8List> exportAnnotatedPdf({
  required PdfDocument document,
  required List<MCard> cards,
  required InkDocument ink,
  double scale = 2.0,
  int jpegQuality = 85,
  void Function(int done, int total)? onProgress,
}) async {
  final out = pw.Document(title: 'mNote export', creator: 'mNote');
  final pages = document.pages;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final jpeg = await renderAnnotatedPage(
      page,
      cards: cards,
      ink: ink,
      scale: scale,
      jpegQuality: jpegQuality,
    );
    final image = pw.MemoryImage(jpeg);
    out.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat(page.width, page.height),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(image, fit: pw.BoxFit.fill),
        ),
      ),
    );
    onProgress?.call(i + 1, pages.length);
  }
  return out.save();
}

/// One page as JPEG bytes with highlights and ink.
Future<Uint8List> renderAnnotatedPage(
  PdfPage page, {
  required List<MCard> cards,
  required InkDocument ink,
  double scale = 2.0,
  int jpegQuality = 85,
}) async {
  final w = (page.width * scale).round(), h = (page.height * scale).round();
  final base = await page.renderForDisplay(
    width: w,
    height: h,
    fullWidth: w.toDouble(),
    fullHeight: h.toDouble(),
    backgroundColor: 0xFFFFFFFF,
  );
  if (base == null)
    throw StateError('Could not render page ${page.pageNumber}');

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(base, Offset.zero, Paint());
  base.dispose();
  canvas.scale(scale);

  // Excerpt highlights (same look as the reader, light theme).
  for (final c in cards) {
    for (final r in c.rects) {
      if (r.page != page.pageNumber) continue;
      final rect = r.toPdfRect().toRect(page: page);
      if (c.image != null) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = c.color.ink()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(0.6),
            const Radius.circular(1.5),
          ),
          Paint()..color = c.color.highlight(),
        );
      }
    }
  }
  paintInk(
    canvas,
    ink.strokesOn(page.pageNumber),
    bounds: Rect.fromLTWH(0, 0, page.width, page.height),
  );

  final composed = await recorder.endRecording().toImage(w, h);
  final rgba = await composed.toByteData(format: ui.ImageByteFormat.rawRgba);
  composed.dispose();
  if (rgba == null) throw StateError('Could not read page ${page.pageNumber}');
  return compute(_encodeJpeg, (rgba.buffer.asUint8List(), w, h, jpegQuality));
}

Uint8List _encodeJpeg((Uint8List, int, int, int) args) {
  final (bytes, w, h, quality) = args;
  final image = im.Image.fromBytes(
    width: w,
    height: h,
    bytes: bytes.buffer,
    numChannels: 4,
  );
  return im.encodeJpg(image, quality: quality);
}

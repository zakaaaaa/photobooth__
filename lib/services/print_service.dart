import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();

  /// Standard print flow for photobooth output.
  /// Landscape images are normalized to portrait before print to avoid crop.
  Future<bool> printStrip(BuildContext context, Uint8List imageBytes,
      {String sessionUuid = 'history',
      int copies = 1,
      String printerKeyword = 'epson',
      String paperSize = '4R'}) async {
    bool printSuccess = false;
    final payload = _preparePrintPayload(
      paperSize: paperSize,
      imageBytes: imageBytes,
    );
    final pdfFormat = payload.pageFormat;
    final printableBytes = payload.printBytes;

    debugPrint(
      'Print resolved | paper_size=$paperSize image_ratio=${payload.imageRatio.toStringAsFixed(4)} resolved_orientation=${payload.orientation} rotated=${payload.rotated}',
    );

    try {
      Future<Uint8List> generateDoc(PdfPageFormat format) async {
        final doc = pw.Document();
        final image = pw.MemoryImage(printableBytes);
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => pw.Container(
              color: PdfColors.white,
              child: pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(image, fit: pw.BoxFit.contain, dpi: 300),
              ),
            ),
          ),
        );
        return doc.save();
      }

      Printer? targetPrinter;
      try {
        final printers = await Printing.listPrinters();
        targetPrinter = printers.firstWhere(
          (p) =>
              p.name.toLowerCase().contains(printerKeyword.toLowerCase()) ||
              p.name.toLowerCase().contains('d500'),
          orElse: () => printers.firstWhere(
            (p) => p.isDefault,
            orElse: () => printers.first,
          ),
        );
      } catch (e) {
        debugPrint('Warning: gagal scan printer: $e');
      }

      if (targetPrinter != null && targetPrinter.isAvailable) {
        for (int i = 0; i < copies; i++) {
          final res = await Printing.directPrintPdf(
            printer: targetPrinter,
            onLayout: (f) async => generateDoc(pdfFormat),
            format: pdfFormat,
            usePrinterSettings: true,
          );
          if (res) printSuccess = true;
          if (copies > 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    } catch (e) {
      debugPrint('Print error: $e');
    }

    if (!printSuccess) {
      try {
        await Printing.layoutPdf(
          onLayout: (format) async {
            final doc = pw.Document();
            final image = pw.MemoryImage(printableBytes);
            doc.addPage(
              pw.Page(
                pageFormat: pdfFormat,
                build: (_) => pw.Container(
                  color: PdfColors.white,
                  child: pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(image, fit: pw.BoxFit.contain, dpi: 300),
                  ),
                ),
              ),
            );
            return doc.save();
          },
          name: 'Photobooth_$sessionUuid',
        );
        printSuccess = true;
      } catch (e) {
        debugPrint('Layout print error: $e');
      }
    }

    return printSuccess;
  }

  _PaperFormatResolution _preparePrintPayload({
    required String paperSize,
    required Uint8List imageBytes,
  }) {
    final decoded = img.decodeImage(imageBytes);
    final width = decoded?.width ?? 1;
    final height = decoded?.height ?? 1;
    final imageRatio = width / height;
    final isLandscape = width > height;

    final normalizedImage = (decoded != null && isLandscape)
        ? img.copyRotate(decoded, angle: 90)
        : decoded;

    final normalizedBytes = normalizedImage == null
        ? imageBytes
        : Uint8List.fromList(img.encodeJpg(normalizedImage, quality: 95));

    switch (paperSize.toUpperCase()) {
      case 'A4':
        return _PaperFormatResolution(
          printBytes: normalizedBytes,
          pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: 0,
            marginTop: 0,
            marginRight: 0,
            marginBottom: 0,
          ),
          orientation: 'portrait',
          imageRatio: imageRatio,
          rotated: isLandscape,
        );
      case 'A5':
        return _PaperFormatResolution(
          printBytes: normalizedBytes,
          pageFormat: PdfPageFormat.a5.copyWith(
            marginLeft: 0,
            marginTop: 0,
            marginRight: 0,
            marginBottom: 0,
          ),
          orientation: 'portrait',
          imageRatio: imageRatio,
          rotated: isLandscape,
        );
      case '4R':
      default:
        return _PaperFormatResolution(
          printBytes: normalizedBytes,
          pageFormat: const PdfPageFormat(4.0 * 72.0, 6.0 * 72.0, marginAll: 0),
          orientation: 'portrait',
          imageRatio: imageRatio,
          rotated: isLandscape,
        );
    }
  }
}

class _PaperFormatResolution {
  final Uint8List printBytes;
  final PdfPageFormat pageFormat;
  final String orientation;
  final double imageRatio;
  final bool rotated;

  const _PaperFormatResolution({
    required this.printBytes,
    required this.pageFormat,
    required this.orientation,
    required this.imageRatio,
    required this.rotated,
  });
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PrintService {
  static final PrintService _instance = PrintService._internal();
  factory PrintService() => _instance;
  PrintService._internal();

  /// Logika cetak standar untuk Photobooth (4R / 4x6 inch)
  Future<bool> printStrip(BuildContext context, Uint8List imageBytes,
      {String sessionUuid = 'history',
      int copies = 1,
      String printerKeyword = 'epson',
      String paperSize = '4R'}) async {
    bool printSuccess = false;

    try {
      final pdfFormat = _paperFormatFor(paperSize);

      Future<Uint8List> generateDoc(PdfPageFormat format) async {
        final doc = pw.Document();
        final image = pw.MemoryImage(imageBytes);
        doc.addPage(pw.Page(
          pageFormat: format,
          build: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300),
          ),
        ));
        return doc.save();
      }

      // Mencoba mencari printer tertentu (Epson/D500) atau Default
      Printer? targetPrinter;
      try {
        final printers = await Printing.listPrinters();
        targetPrinter = printers.firstWhere(
          (p) =>
              p.name.toLowerCase().contains(printerKeyword.toLowerCase()) ||
              p.name.toLowerCase().contains("d500"),
          orElse: () => printers.firstWhere((p) => p.isDefault,
              orElse: () => printers.first),
        );
      } catch (e) {
        debugPrint("⚠️ Gagal scan printer: $e");
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
          // Beri sedikit jeda antar spool jika perlu (opsional)
          if (copies > 1) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Print error: $e");
    }

    // Fallback: Jika direct print gagal, gunakan layout picker standard
    if (!printSuccess) {
      try {
        await Printing.layoutPdf(
          onLayout: (format) async {
            final doc = pw.Document();
            final image = pw.MemoryImage(imageBytes);
            doc.addPage(pw.Page(
              pageFormat: _paperFormatFor(paperSize),
              build: (_) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(image, fit: pw.BoxFit.cover, dpi: 300),
              ),
            ));
            return doc.save();
          },
          name: 'Photobooth_$sessionUuid',
        );
        printSuccess = true; // Anggap sukses jika jendela print terbuka
      } catch (e) {
        debugPrint("❌ Layout Print error: $e");
      }
    }

    return printSuccess;
  }

  PdfPageFormat _paperFormatFor(String paperSize) {
    switch (paperSize.toUpperCase()) {
      case 'A4':
        return PdfPageFormat.a4.copyWith(
          marginLeft: 0,
          marginTop: 0,
          marginRight: 0,
          marginBottom: 0,
        );
      case 'A5':
        return PdfPageFormat.a5.copyWith(
          marginLeft: 0,
          marginTop: 0,
          marginRight: 0,
          marginBottom: 0,
        );
      case '4R':
      default:
        return const PdfPageFormat(4.0 * 72.0, 6.0 * 72.0, marginAll: 0);
    }
  }
}

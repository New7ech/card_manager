import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import 'file_service.dart';

class PdfService {
  static const double _a4WidthMm  = 210.0;
  static const double _a4HeightMm = 297.0;

  static const double _cardWidthMm  = 86.9 + 4.0; // 90.9 mm
  static const double _cardHeightMm = 54.0 + 4.0; // 58.0 mm

  static const int    _columns  = 2;
  static const int    _rows     = 5;
  static const double _spaceXMm = 14.0;
  static const double _spaceYMm = 1.0;
  static const double _ptPerMm  = 2.83465;

  static double get _marginXMm {
    final gridWidth = (_columns * _cardWidthMm) + ((_columns - 1) * _spaceXMm);
    return (_a4WidthMm - gridWidth) / 2.0;
  }

  static double get _marginYMm {
    final gridHeight = (_rows * _cardHeightMm) + ((_rows - 1) * _spaceYMm);
    return (_a4HeightMm - gridHeight) / 2.0;
  }

  /// Génère un PDF en grille A4.
  /// Images : intégrées directement.
  /// PDFs   : première page rendue en image via pdfx (fallback placeholder).
  static Future<File> generateCardGridPdf(
    List<File> files,
    String outputFilePath,
  ) async {
    final pdf = pw.Document();
    final maxPerPage = _columns * _rows;

    for (int start = 0; start < files.length; start += maxPerPage) {
      final pageFiles = files.sublist(
        start,
        (start + maxPerPage).clamp(0, files.length),
      );

      final widgets = await Future.wait(
        pageFiles.map((f) => _fileToWidget(f)),
      );

      pdf.addPage(_buildPage(widgets));
    }

    final out = File(outputFilePath);
    await out.writeAsBytes(await pdf.save());
    return out;
  }

  static Future<pw.Widget> _fileToWidget(File file) async {
    if (FileService.isPdf(file.path)) {
      try {
        final imageBytes = await _renderPdfFirstPage(file.path);
        return pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.fill);
      } catch (_) {
        // Rendu échoué → placeholder avec nom du fichier
        final name = file.path.split(RegExp(r'[\\/]')).last;
        return _buildPdfPlaceholder(name);
      }
    }
    final bytes = await file.readAsBytes();
    return pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill);
  }

  /// Rend la première page d'un PDF en PNG via pdfx (pdfium natif).
  static Future<Uint8List> _renderPdfFirstPage(String filePath) async {
    final document = await pdfx.PdfDocument.openFile(filePath);
    try {
      final page = await document.getPage(1);
      try {
        // Résolution 2× pour une bonne qualité sur la grille imprimée
        final rendered = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: pdfx.PdfPageImageFormat.png,
        );
        return rendered!.bytes;
      } finally {
        await page.close();
      }
    } finally {
      await document.close();
    }
  }

  static pw.Widget _buildPdfPlaceholder(String filename) {
    final name = filename.endsWith('.pdf')
        ? filename.substring(0, filename.length - 4)
        : filename;

    return pw.Container(
      decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      padding: const pw.EdgeInsets.all(8),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'PDF',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey700,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            name,
            maxLines: 2,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.blueGrey600),
          ),
        ],
      ),
    );
  }

  static pw.Page _buildPage(List<pw.Widget> widgets) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (_) => pw.Stack(
        children: List.generate(widgets.length, (index) {
          final col = index % _columns;
          final row = index ~/ _columns;
          final x = _marginXMm + col * (_cardWidthMm + _spaceXMm);
          final y = _marginYMm + row * (_cardHeightMm + _spaceYMm);

          return pw.Positioned(
            left: x * _ptPerMm,
            top:  y * _ptPerMm,
            child: pw.SizedBox(
              width:  _cardWidthMm * _ptPerMm,
              height: _cardHeightMm * _ptPerMm,
              child: widgets[index],
            ),
          );
        }),
      ),
    );
  }
}

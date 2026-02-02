import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/pnl_entry.dart';
import 'pnl_calculation_service.dart';

/// Service for generating P&L PDF reports
class PnlPdfService {
  static final _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final _percentFormat = NumberFormat('0.0', 'en_US');

  /// Generate and show save dialog for P&L PDF
  static Future<void> generateAndSavePdf({
    required PnlPeriod period,
    required List<PnlLineItem> lineItems,
    required String storeName,
    required String storeNsn,
  }) async {
    final pdfBytes = await _generatePdf(
      period: period,
      lineItems: lineItems,
      storeName: storeName,
      storeNsn: storeNsn,
    );

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'PnL_${period.periodDisplay.replaceAll(', ', '_')}.pdf',
    );
  }

  static Future<Uint8List> _generatePdf({
    required PnlPeriod period,
    required List<PnlLineItem> lineItems,
    required String storeName,
    required String storeNsn,
  }) async {
    final pdf = pw.Document();

    // Get product net sales for percentage calculations
    final productNetSales = lineItems
        .firstWhere(
          (i) => i.label == 'PRODUCT NET SALES',
          orElse: () => PnlLineItem(periodId: 0, label: '', sortOrder: 0, category: PnlCategory.sales),
        )
        .value;

    final goalPercent = PnlCalculationService.getGoalPercentage(lineItems);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        storeName.isNotEmpty ? storeName : 'P&L Projections',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      if (storeNsn.isNotEmpty)
                        pw.Text(
                          storeNsn,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  pw.Text(
                    period.periodDisplay,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Column headers
              pw.Container(
                color: PdfColors.grey300,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(''),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'PROJECTED \$',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'PROJECTED %',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'COMMENTS',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Data rows
              ...lineItems.map((item) => _buildPdfRow(item, productNetSales, goalPercent, period.avgWage)),

              // Avg Wage note at bottom
              if (period.avgWage > 0) ...[
                pw.SizedBox(height: 16),
                pw.Text(
                  'Avg Wage: ${_currencyFormat.format(period.avgWage)}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildPdfRow(
    PnlLineItem item,
    double productNetSales,
    double goalPercent,
    double avgWage,
  ) {
    final isGoalRow = item.label == 'GOAL';
    final percent = isGoalRow
        ? goalPercent
        : PnlCalculationService.calculatePercentage(item.value, productNetSales);

    // Determine row color
    PdfColor? rowColor;
    if (item.label == 'P.A.C.') {
      rowColor = PdfColors.cyan100;
    } else if (item.isCalculated) {
      rowColor = PdfColors.yellow100;
    } else if (item.category == PnlCategory.sales) {
      rowColor = PdfColors.green50;
    }

    // Check for section breaks
    final needsTopBorder = [
      'FOOD COST',
      'LABOR - MANAGEMENT',
      'PAYROLL TAXES',
      'P.A.C.',
    ].contains(item.label);

    // Build comment text (include Avg Wage for LABOR - CREW)
    String commentText = item.comment;
    if (item.label == 'LABOR - CREW' && avgWage > 0) {
      commentText = '${item.comment}${item.comment.isNotEmpty ? ' | ' : ''}Avg Wage: ${_currencyFormat.format(avgWage)}';
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: rowColor,
        border: needsTopBorder
            ? const pw.Border(top: pw.BorderSide(width: 1.5))
            : null,
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                item.label,
                style: pw.TextStyle(
                  fontWeight: item.isCalculated ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                _currencyFormat.format(item.value),
                style: pw.TextStyle(
                  fontWeight: item.isCalculated ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 10,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ),
          pw.Expanded(
            flex: 1,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                '${_percentFormat.format(percent)}%',
                style: pw.TextStyle(
                  fontWeight: item.isCalculated ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 10,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: pw.Text(
                commentText,
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

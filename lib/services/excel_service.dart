import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/receipt_data.dart';

/// Service for exporting receipt OCR results to Excel spreadsheets.
class ExcelService {
  static final ExcelService _instance = ExcelService._();
  factory ExcelService() => _instance;
  ExcelService._();

  /// Create an Excel file from receipt data and return the file path.
  Future<String> createExcel(
      List<ReceiptData> receipts, String supplierName) async {
    final excel = Excel.createExcel();
    final sheet = excel['Receipts'];

    // Set column widths
    final headers = ReceiptData.excelHeaders;
    for (int i = 0; i < headers.length; i++) {
      sheet.setColumnWidth(i.toInt(), 20);
    }

    // Header row
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#FF6B35'),
      fontFamily: getFontFamily(FontFamily.Calibri),
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 0,
      ));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }
    sheet.setDefaultRowHeight(20);

    // Data rows
    for (int r = 0; r < receipts.length; r++) {
      final row = receipts[r].toExcelRow();
      for (int c = 0; c < row.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: c,
          rowIndex: r + 1,
        ));
        final value = row[c];
        if (value is double) {
          cell.value = DoubleCellValue(value);
        } else {
          cell.value = TextCellValue(value?.toString() ?? '');
        }
      }
    }

    // Item rows (individual items from the item table)
    final itemSheet = excel['Items'];
    final itemHeaders = [
      'Receipt File',
      'Qty',
      'Description',
      'Unit Price',
      'Discount',
      'Amount',
    ];
    final itemHeaderStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#FF6B35'),
      fontFamily: getFontFamily(FontFamily.Calibri),
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (int i = 0; i < itemHeaders.length; i++) {
      final cell = itemSheet.cell(CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 0,
      ));
      cell.value = TextCellValue(itemHeaders[i]);
      cell.cellStyle = itemHeaderStyle;
    }

    int itemRow = 1;
    for (final receipt in receipts) {
      for (final item in receipt.items) {
        final itemCells = itemSheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: itemRow));
        itemCells.value = TextCellValue(receipt.filename);

        itemSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: itemRow))
            .value = IntCellValue(item.quantity);

        itemSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: itemRow))
            .value = TextCellValue(item.description);

        itemSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: itemRow))
            .value = DoubleCellValue(item.unitPrice);

        itemSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: itemRow))
            .value = DoubleCellValue(item.discount);

        itemSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: itemRow))
            .value = DoubleCellValue(item.amount);

        itemRow++;
      }
    }

    // Save file
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${appDir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeName = supplierName.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final filename = '${safeName}_$timestamp.xlsx';
    final filePath = '${downloadsDir.path}/$filename';

    final fileBytes = excel.encode();
    if (fileBytes == null) throw Exception('Failed to encode Excel file');

    await File(filePath).writeAsBytes(fileBytes);
    return filePath;
  }

  /// Share the Excel file via the system share sheet.
  Future<void> shareExcel(String filePath, String supplierName) async {
    final file = XFile(filePath, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    await Share.shareXFiles(
      [file],
      subject: 'IntelliOCR Report - $supplierName',
      text: 'IntelliOCR receipt report for $supplierName',
    );
  }

  /// Share an Excel file via system share (Gmail available in options).
  Future<void> shareViaGmail(String filePath, String supplierName) async {
    final file = XFile(filePath);
    await Share.shareXFiles(
      [file],
      subject: 'IntelliOCR Report - $supplierName',
      text: 'IntelliOCR receipt processing results for $supplierName\n\nProcessed at: ${DateTime.now().toString()}',
    );
  }

  /// Share Excel via native Android Gmail intent with file attachment.
  /// Works on APK (native intent); falls back to web compose on desktop.
  Future<void> shareViaGmailWithAttachment(String filePath, String supplierName) async {
    // Use share_plus XFiles for native Android Gmail intent (supports attachment)
    final file = XFile(
      filePath,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await Share.shareXFiles(
      [file],
      subject: 'IntelliOCR Report - $supplierName',
      text: 'IntelliOCR receipt report for $supplierName\n'
          'Processed: ${DateTime.now().toString().split('.').first}\n'
          'Source: IntelliOCR Scanner',
    );
  }
}

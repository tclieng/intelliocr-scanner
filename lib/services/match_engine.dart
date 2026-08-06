import 'dart:io';
import 'dart:ui' as ui;
import '../models/receipt_template.dart';
import '../models/field_roi.dart';
import '../models/receipt_data.dart';
import '../services/ocr_service.dart';

/// Result of anchor matching on a captured receipt image.
class AnchorMatchResult {
  final bool matched;
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;
  final String? matchedAnchorA;
  final String? matchedAnchorB;
  final String? matchedAnchorC;
  final double confidence;

  AnchorMatchResult({
    required this.matched,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.matchedAnchorA,
    this.matchedAnchorB,
    this.matchedAnchorC,
    this.confidence = 0.0,
  });

  ui.Rect mapRoi(ui.Rect templateRoi) {
    return ui.Rect.fromLTRB(
      templateRoi.left * scaleX + offsetX,
      templateRoi.top * scaleY + offsetY,
      templateRoi.right * scaleX + offsetX,
      templateRoi.bottom * scaleY + offsetY,
    );
  }
}

/// Lightweight OCR block with position info.
class OcrBlock {
  final String text;
  final double x, y, width, height;

  OcrBlock({
    required this.text,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  double get centerX => x + width / 2;
  double get centerY => y + height / 2;
}

/// Engine for matching receipt templates using OCR-based anchor detection.
class MatchEngine {
  static final MatchEngine _instance = MatchEngine._();
  factory MatchEngine() => _instance;
  MatchEngine._();

  final OcrService _ocr = OcrService();

  // ── Block extraction ──

  Future<List<OcrBlock>> _getBlocks(File imageFile) async {
    final result = await _ocr.recognizeDetailed(imageFile);
    if (result == null) return [];

    final blocks = <OcrBlock>[];
    for (final block in result.blocks) {
      final lines = block.lines;
      final text = lines.map((l) => l.text).join(' ').trim();
      if (text.isEmpty) continue;

      double minX = double.infinity, minY = double.infinity;
      double maxX = 0, maxY = 0;
      for (final line in lines) {
        for (final element in line.elements) {
          final rect = element.boundingBox;
          if (rect != null) {
            if (rect.left < minX) minX = rect.left.toDouble();
            if (rect.top < minY) minY = rect.top.toDouble();
            if (rect.right > maxX) maxX = rect.right.toDouble();
            if (rect.bottom > maxY) maxY = rect.bottom.toDouble();
          }
        }
      }

      if (minX.isFinite && minY.isFinite) {
        blocks.add(OcrBlock(
          text: text,
          x: minX,
          y: minY,
          width: maxX - minX,
          height: maxY - minY,
        ));
      }
    }
    return blocks;
  }

  // ── Template matching ──

  Future<AnchorMatchResult> matchTemplate(
    ReceiptTemplate template,
    File capturedFile,
    double capturedWidth,
    double capturedHeight,
  ) async {
    final blocks = await _getBlocks(capturedFile);
    if (blocks.isEmpty) return AnchorMatchResult(matched: false);

    final allText = blocks.map((b) => b.text).join('\n').toLowerCase();

    String? matchedA;
    double? ax, ay;
    if (template.anchorA != null && template.anchorA!.expectedText.isNotEmpty) {
      final expA = template.anchorA!.expectedText;
      matchedA = _findBestMatch(expA.toLowerCase(), blocks, allText);
      if (matchedA != null) {
        final block = blocks.firstWhere(
          (b) => b.text.toLowerCase().contains(expA.toLowerCase()),
          orElse: () => blocks.first,
        );
        ax = block.x + block.width / 2;
        ay = block.y + block.height / 2;
      }
    }

    String? matchedB;
    double? bx, by;
    if (template.anchorB != null && template.anchorB!.expectedText.isNotEmpty) {
      final expB = template.anchorB!.expectedText;
      matchedB = _findBestMatch(expB.toLowerCase(), blocks, allText);
      if (matchedB != null) {
        final block = blocks.firstWhere(
          (b) => b.text.toLowerCase().contains(expB.toLowerCase()),
          orElse: () => blocks.first,
        );
        bx = block.x + block.width / 2;
        by = block.y + block.height / 2;
      }
    }

    String? matchedC;
    if (template.anchorC != null && template.anchorC!.expectedText.isNotEmpty) {
      final expC = template.anchorC!.expectedText;
      matchedC = _findBestMatch(expC.toLowerCase(), blocks, allText);
    }

    double scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0;
    final tW = template.masterWidth > 0 ? template.masterWidth : capturedWidth;
    final tH = template.masterHeight > 0 ? template.masterHeight : capturedHeight;
    scaleX = capturedWidth / tW;
    scaleY = capturedHeight / tH;

    if (matchedA != null && ax != null && ay != null && template.anchorA != null) {
      final tA = template.anchorA!;
      offsetX = ax - tA.roi.left * scaleX;
      offsetY = ay - tA.roi.top * scaleY;
    } else if (matchedB != null && bx != null && by != null && template.anchorB != null) {
      final tB = template.anchorB!;
      offsetX = bx - tB.roi.left * scaleX;
      offsetY = by - tB.roi.top * scaleY;
    }

    int matchedCount = [matchedA, matchedB, matchedC].where((m) => m != null).length;
    double confidence = matchedCount / 3.0;

    return AnchorMatchResult(
      matched: matchedA != null || matchedB != null,
      scaleX: scaleX,
      scaleY: scaleY,
      offsetX: offsetX,
      offsetY: offsetY,
      matchedAnchorA: matchedA,
      matchedAnchorB: matchedB,
      matchedAnchorC: matchedC,
      confidence: confidence,
    );
  }

  String? _findBestMatch(String expected, List<OcrBlock> blocks, String allText) {
    if (allText.contains(expected)) return expected;

    final keywords = expected.split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
    if (keywords.isNotEmpty) {
      final found = keywords.where((k) => allText.contains(k)).toList();
      if (found.length >= keywords.length * 0.6) {
        found.sort((a, b) => b.length.compareTo(a.length));
        return found.first;
      }
    }

    for (final block in blocks) {
      final bt = block.text.toLowerCase();
      if (_levenshteinSimilarity(bt, expected) > 0.7) return block.text;
      if (bt.startsWith(expected) || expected.startsWith(bt)) return block.text;
    }

    return null;
  }

  double _levenshteinSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final dist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1.0 - dist / maxLen;
  }

  int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final matrix = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));
    for (int i = 0; i <= a.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= b.length; j++) matrix[0][j] = j;
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[a.length][b.length];
  }

  // ── Main extraction ──

  Future<ReceiptData> extractWithTemplate(
    ReceiptTemplate template,
    File capturedFile,
    double capturedWidth,
    double capturedHeight,
    String filename,
  ) async {
    final result = await matchTemplate(template, capturedFile, capturedWidth, capturedHeight);
    final data = ReceiptData(filename: filename);

    if (!result.matched) {
      data.description = 'Template not matched — low confidence';
      final rawText = await _ocr.recognizeText(capturedFile);
      _fillFromFullOcr(data, rawText);
      return data;
    }

    final blocks = await _getBlocks(capturedFile);
    final rawText = await _ocr.recognizeText(capturedFile);

    // Find Anchor C position for item table bottom boundary
    double? anchorCY;
    if (result.matchedAnchorC != null) {
      final lower = result.matchedAnchorC!.toLowerCase();
      for (final b in blocks) {
        if (b.text.toLowerCase().contains(lower)) {
          anchorCY = b.y;
          break;
        }
      }
    }

    // Extract configured field ROIs (ROI Fields from template editor)
    for (final field in template.fields) {
      final mappedRoi = result.mapRoi(field.roi);
      final useDual = field.ocrEngine == 'both';
      final croppedText = await _extractRoiText(capturedFile, mappedRoi, useDual: useDual);
      _populateField(data, field.fieldName, croppedText.trim(), blocks);
    }

    // Extract TOTAL from GREEN box (anchorC) if defined — most reliable source
    if (template.anchorC != null && template.anchorC!.roi != ui.Rect.zero) {
      final greenRoi = result.mapRoi(template.anchorC!.roi);
      final greenText = await _extractRoiText(capturedFile, greenRoi, useDual: true);
      final gv = _extractDecimal(greenText);
      if (gv > 0) data.amount = gv;
    }

    // Extract item rows from YELLOW box (new, column-based, subtotal-delimiter rows)
    if (template.yellowBoxConfig != null) {
      data.items = await _extractYellowBox(
        template.yellowBoxConfig!,
        result,
        capturedFile,
        blocks,
        anchorCY,
      );
    } else if (template.itemTableConfig != null) {
      // Legacy fallback for pre-yellowbox templates
      data.items = await _extractItemTable(
        template.itemTableConfig!,
        result,
        capturedFile,
        blocks,
        anchorCY,
      );
    }

    _fillFromFullOcr(data, rawText);

    data.confidence = result.confidence;
    data.isValidated = result.confidence >= 0.3;
    return data;
  }

  Future<String> _extractRoiText(File imageFile, ui.Rect roi, {bool useDual = false}) async {
    final clamped = ui.Rect.fromLTRB(
      roi.left.clamp(0.0, double.infinity),
      roi.top.clamp(0.0, double.infinity),
      roi.right.clamp(0.0, double.infinity),
      roi.bottom.clamp(0.0, double.infinity),
    );
    if (clamped.width < 5 || clamped.height < 5) return '';
    try {
      if (useDual) {
        final dualResult = await _ocr.recognizeRoiDual(imageFile, clamped);
        return dualResult.fusedText;
      }
      return await _ocr.recognizeRoi(imageFile, clamped);
    } catch (e) {
      return '';
    }
  }

  // ── Field population (FIXED: now handles ALL field types) ──

  void _populateField(ReceiptData data, String fieldName, String text, List<OcrBlock> blocks) {
    if (text.isEmpty) return;
    switch (fieldName) {
      // Predefined standard fields
      case 'store_name':
        if (data.supplier.isEmpty) data.supplier = text;
        break;
      case 'date':
        final m = RegExp(r'(\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})').firstMatch(text);
        if (m != null) data.date = m.group(1)!;
        break;
      case 'time':
        final m = RegExp(r'(\d{1,2}:\d{2}(:\d{2})?)').firstMatch(text);
        if (m != null) data.time = m.group(1)!;
        break;
      case 'receipt_number':
        if (data.number.isEmpty) data.number = text;
        break;
      case 'cashier':
        data.cashier = text;
        break;
      case 'terminal_id':
        data.terminalId = text;
        break;
      case 'currency':
        data.currency = text.length <= 5 ? text : 'RM';
        break;
      case 'tax':
        final v = _extractDecimal(text);
        if (v > 0) data.tax = v;
        break;
      case 'subtotal':
        final v = _extractDecimal(text);
        if (v > 0) data.subtotal = v;
        break;
      case 'total':
        final v = _extractDecimal(text);
        if (v > 0) data.amount = v;
        break;
      case 'payment_method':
        data.paymentMethod = text;
        break;
      case 'membership_number':
        data.membershipNumber = text;
        break;
      case 'service_charge':
        // Handled via custom fields
        data.customFields['service_charge'] = text;
        break;
      // ── Custom ROI fields (user-defined in template editor) ──
      case 'item_description':
        // Single-line ROI text: extract the product description text
        // Usually contains product name, remove trailing numbers/amounts
        final cleanText = _cleanItemDescription(text);
        if (cleanText.isNotEmpty) data.description = cleanText;
        break;
      case 'unit_price':
        final v = _extractDecimal(text);
        if (v > 0) {
          data.customFields['unit_price'] = v.toStringAsFixed(2);
        }
        break;
      case 'quantity':
        final qty = _extractInteger(text);
        if (qty > 0) data.customFields['quantity'] = qty.toString();
        break;
      case 'discount':
        final v = _extractDecimal(text);
        if (v > 0) {
          data.customFields['discount'] = v.toStringAsFixed(2);
        }
        break;
      case 'custom_field':
        // Generic custom field — skip (handled elsewhere)
        break;
    }
  }

  /// Clean item description text: remove trailing prices/quantities that OCR may include.
  String _cleanItemDescription(String text) {
    // Remove trailing numbers (prices, quantities) from description
    var cleaned = text
        .replaceAll(RegExp(r'\s*\d+[xX×]\s*$'), '') // e.g. "2x"
        .replaceAll(RegExp(r'\s*[\d,]+\.\d{2}\s*$'), '') // e.g. " 12.50"
        .replaceAll(RegExp(r'\s*RM\s*[\d,]+\.?\d*\s*$', caseSensitive: false), '') // " RM 12.50"
        .trim();
    // If the whole thing is just a number, return empty
    if (RegExp(r'^[\d\s,.]+$').hasMatch(cleaned)) return '';
    return cleaned;
  }

  /// Extract integer from text (for quantity, etc.)
  int _extractInteger(String text) {
    final m = RegExp(r'\b(\d+)\b').firstMatch(text);
    if (m == null) return 0;
    return int.tryParse(m.group(1)!) ?? 0;
  }

  // ── YELLOW box extraction (column-based, subtotal-delimiter row detection) ──

  /// Extract item rows from the YELLOW box using user-defined columns.
  /// Rows are delimited by a decimal value in the `amount` column (the per-line
  /// subtotal). Description-only rows that precede an amount row are merged into
  /// it, which handles wrapped item names that spill onto a second line.
  Future<List<ItemRow>> _extractYellowBox(
    YellowBoxConfig cfg,
    AnchorMatchResult match,
    File imageFile,
    List<OcrBlock> blocks,
    double? anchorCY,
  ) async {
    final items = <ItemRow>[];
    if (cfg.columns.isEmpty) return items;

    final mappedYellow = match.mapRoi(cfg.roi);
    final topY = mappedYellow.top;
    final bottomY = anchorCY != null ? anchorCY : mappedYellow.bottom;
    final leftX = mappedYellow.left;
    final rightX = mappedYellow.right;
    final scaleX = match.scaleX;

    final cols = cfg.sortedColumns;
    double colLeft(int i) => leftX + cols[i].x * scaleX;
    double colRight(int i) => leftX + (cols[i].x + cols[i].width) * scaleX;

    // Index of the amount (subtotal) column — rightmost decimal delimiter.
    int amountIdx = cols.indexWhere((c) => c.name == 'amount');
    if (amountIdx < 0) amountIdx = cols.length - 1;

    int columnOf(OcrBlock b) {
      final cx = b.centerX;
      for (int i = 0; i < cols.length; i++) {
        if (cx >= colLeft(i) - 4 && cx <= colRight(i) + 4) return i;
      }
      int best = 0;
      double bestD = double.infinity;
      for (int i = 0; i < cols.length; i++) {
        final center = (colLeft(i) + colRight(i)) / 2;
        final d = (cx - center).abs();
        if (d < bestD) {
          bestD = d;
          best = i;
        }
      }
      return best;
    }

    final tol = 8.0;
    final yellowBlocks = blocks.where((b) {
      final cy = b.centerY;
      final cx = b.centerX;
      return cy >= topY - tol &&
          cy <= bottomY + tol &&
          cx >= leftX - tol &&
          cx <= rightX + tol;
    }).toList();

    if (yellowBlocks.isEmpty) return items;

    yellowBlocks.sort((a, b) {
      final dy = a.y - b.y;
      if (dy.abs() > 6) return dy.round();
      return a.x.compareTo(b.x);
    });

    final rawRows = _groupBlocksIntoRows(yellowBlocks);

    bool rowHasAmount(List<OcrBlock> row) {
      for (final b in row) {
        if (columnOf(b) == amountIdx) {
          if (_extractDecimal(b.text) > 0) return true;
        }
      }
      return false;
    }

    String pendingDesc = '';
    final requireAmount = cfg.detectRowsBySubtotal;

    for (final row in rawRows) {
      final colText = <int, List<String>>{};
      for (final b in row) {
        final ci = columnOf(b);
        (colText[ci] ??= []).add(b.text.trim());
      }

      var hasAmount = rowHasAmount(row);
      if (!requireAmount) hasAmount = true;

      String descText = (colText[0] ?? []).join(' ').trim();

      if (!hasAmount) {
        // Description-only continuation (wrapped name or header) — buffer it.
        final low = descText.toLowerCase();
        final isHeader = low.contains('item') ||
            low.contains('qty') ||
            low.contains('price') ||
            low.contains('amt') ||
            low.contains('description') ||
            low.contains('unit');
        if (!isHeader && descText.isNotEmpty) {
          pendingDesc =
              pendingDesc.isEmpty ? descText : '$pendingDesc $descText';
        }
        continue;
      }

      // Amount row — merge any buffered leading description lines.
      if (pendingDesc.isNotEmpty) {
        descText = descText.isEmpty ? pendingDesc : '$pendingDesc $descText';
        pendingDesc = '';
      }

      if (_isNonItemText(descText.toLowerCase())) continue;

      int qty = 1;
      double unitPrice = 0, discount = 0, amount = 0;

      for (int i = 0; i < cols.length; i++) {
        final name = cols[i].name;
        final txt = (colText[i] ?? []).join(' ').trim();
        if (txt.isEmpty) continue;
        switch (name) {
          case 'quantity':
            final q = _extractInteger(txt);
            if (q > 0) qty = q;
            break;
          case 'unit_price':
            final v = _extractDecimal(txt);
            if (v > 0) unitPrice = v;
            break;
          case 'discount':
            final v = _extractDecimal(txt);
            if (v > 0) discount = v;
            break;
          case 'amount':
            final v = _extractDecimal(txt);
            if (v > 0) amount = v;
            break;
          default:
            if (name == 'item_description' && descText.isEmpty) {
              descText = _cleanItemDescription(txt);
            }
        }
      }

      descText = descText.trim();
      if (descText.isEmpty) continue;
      if (amount == 0 && unitPrice > 0) amount = unitPrice * qty;

      items.add(ItemRow(
        quantity: qty,
        description: descText,
        unitPrice: unitPrice,
        discount: discount,
        amount: amount,
      ));
    }

    return items;
  }

  // ── Item table extraction (improved for thermal receipts) ──

  Future<List<ItemRow>> _extractItemTable(
    ItemTableConfig config,
    AnchorMatchResult match,
    File imageFile,
    List<OcrBlock> blocks,
    double? anchorCY,
  ) async {
    final items = <ItemRow>[];

    // Map ROI regions
    final tableTop = match.mapRoi(config.tableRoi).top;
    // Use Anchor C Y position if found; otherwise use template table bottom
    final tableBottom = anchorCY != null
        ? anchorCY
        : match.mapRoi(config.tableRoi).bottom;

    // Filter blocks that fall within the table vertical range
    final tableBlocks = blocks
        .where((b) => b.y >= tableTop - 30 && b.y <= tableBottom + 30)
        .toList();

    // Sort blocks by vertical position first, then horizontal
    tableBlocks.sort((a, b) {
      final dy = a.y - b.y;
      if (dy.abs() > 20) return dy.round();
      return a.x.compareTo(b.x);
    });

    // Column boundary X positions (mapped from template to captured)
    final descLeft = match.mapRoi(config.descriptionColumn).left;
    final priceLeft = match.mapRoi(config.unitPriceColumn).left;
    final amountLeft = match.mapRoi(config.amountColumn).left;

    // Group blocks into rows using Y-coordinate clustering
    final rows = _groupBlocksIntoRows(tableBlocks);

    for (final rowBlocks in rows) {
      // Sort by X within each row
      rowBlocks.sort((a, b) => a.x.compareTo(b.x));

      String desc = '';
      int? qty;
      double? price;
      double? amount;

      for (final block in rowBlocks) {
        final cx = block.centerX;
        final text = block.text.trim();

        if (text.isEmpty) continue;

        // Skip separator lines and non-item text
        final lower = text.toLowerCase();
        if (_isNonItemText(lower)) continue;

        if (cx < descLeft) {
          // Left column: quantity
          final n = _extractInteger(text);
          if (n > 0 && qty == null) qty = n;
          // Also check for "price × qty" format like "12.50×2"
          final priceQty = RegExp(r'([\d,]+\.?\d*)\s*[xX×]\s*(\d+)').firstMatch(text);
          if (priceQty != null) {
            final p = double.tryParse(priceQty.group(1)!.replaceAll(',', ''));
            final q = int.tryParse(priceQty.group(2)!);
            if (p != null && p > 0 && price == null) price = p;
            if (q != null && q > 0 && qty == null) qty = q;
          }
        } else if (cx < priceLeft) {
          // Middle column: description
          if (desc.isNotEmpty) desc += ' ';
          desc += text;
        } else if (cx < amountLeft) {
          // Price column: unit price
          final v = _extractDecimal(text);
          if (v > 0 && price == null) price = v;
        } else {
          // Amount column: line total
          final v = _extractDecimal(text);
          if (v > 0 && amount == null) amount = v;
        }
      }

      desc = desc.trim();
      if (desc.isEmpty) continue;

      // Skip non-item rows
      final lower = desc.toLowerCase();
      if (_isNonItemText(lower)) continue;

      // Compute amount from price × qty if not extracted
      if (amount == null && price != null) {
        amount = price * (qty ?? 1);
      }

      items.add(ItemRow(
        quantity: qty ?? 1,
        description: desc,
        unitPrice: price ?? 0,
        amount: amount ?? price ?? 0,
      ));
    }

    return items;
  }

  /// Check if text should be excluded from item rows.
  bool _isNonItemText(String text) {
    if (text.isEmpty) return true;
    final nonItemKeywords = [
      'subtotal', 'total', 'tax', 'gst', 'sst', 'service charge',
      'payment', 'cash', 'change', 'card', 'visa', 'mastercard',
      'rounding', 'grand total', 'amount', 'payable', 'balance',
      'total item', 'total qty', 'total saving', 'item count',
      'thank you', 'please', 'welcome', 'receipt', 'invoice',
      'copy', 'original', 'return', 'exchange',
    ];
    for (final kw in nonItemKeywords) {
      if (text.contains(kw)) return true;
    }
    // Skip if it's mostly numbers
    if (RegExp(r'^[\d\s,.xX×-]+$').hasMatch(text)) return true;
    // Skip barcodes (long sequences of numbers)
    if (RegExp(r'^\d{8,}$').hasMatch(text)) return true;
    return false;
  }

  /// Group OCR blocks into rows using adaptive Y clustering.
  List<List<OcrBlock>> _groupBlocksIntoRows(List<OcrBlock> blocks) {
    if (blocks.isEmpty) return [];

    final rows = <List<OcrBlock>>[];
    var currentRow = <OcrBlock>[blocks.first];

    for (int i = 1; i < blocks.length; i++) {
      final block = blocks[i];
      final lastBlock = currentRow.last;
      // Use adaptive threshold: 8% of average block height in the row
      final avgHeight = currentRow.fold<double>(0, (sum, b) => sum + b.height) / currentRow.length;
      final threshold = avgHeight * 0.8 + 8; // At least 8px gap

      if ((block.y - lastBlock.y).abs() <= threshold) {
        currentRow.add(block);
      } else {
        if (currentRow.isNotEmpty) rows.add(currentRow);
        currentRow = [block];
      }
    }
    if (currentRow.isNotEmpty) rows.add(currentRow);

    return rows;
  }

  // ── Full-page OCR fallback (Priority 3) ──

  void _fillFromFullOcr(ReceiptData data, String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // ── Date ──
    if (data.date.isEmpty) {
      for (final line in lines) {
        final m = RegExp(r'(\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})').firstMatch(line);
        if (m != null) { data.date = m.group(1)!; break; }
      }
    }

    // ── Time ──
    if (data.time.isEmpty) {
      for (final line in lines) {
        final m = RegExp(r'(\d{1,2}:\d{2})').firstMatch(line);
        if (m != null) { data.time = m.group(1)!; break; }
      }
    }

    // ── Receipt number ──
    if (data.number.isEmpty) {
      for (final line in lines) {
        final m = RegExp(r'(?:Receipt|Invoice|PV|Inv)[#\s:]*([\w/-]+)', caseSensitive: false).firstMatch(line);
        if (m != null) { data.number = m.group(1)!.trim(); break; }
      }
    }

    // ── Supplier name (if not already set) ──
    if (data.supplier.isEmpty && lines.isNotEmpty) {
      // Use first non-empty line as supplier if it looks like a name
      for (final line in lines.take(3)) {
        if (line.length >= 3 && !RegExp(r'^\d').hasMatch(line) &&
            !line.contains(RegExp(r'[\d]{6,}'))) {
          data.supplier = line;
          break;
        }
      }
    }

    // ── Payment method ──
    if (data.paymentMethod.isEmpty) {
      final all = rawText.toLowerCase();
      if (all.contains('cash')) data.paymentMethod = 'Cash';
      else if (all.contains('visa')) data.paymentMethod = 'Visa';
      else if (all.contains('mastercard')) data.paymentMethod = 'Mastercard';
      else if (all.contains('tng') || all.contains('touch')) data.paymentMethod = 'TNG eWallet';
      else if (all.contains('boost')) data.paymentMethod = 'Boost';
      else if (all.contains('grabpay')) data.paymentMethod = 'GrabPay';
      else if (all.contains('debit') || all.contains('credit')) data.paymentMethod = 'Card';
    }

    // ── TOTAL amount (Priority strategy) ──
    if (data.amount == 0) {
      _extractTotalFromFullOcr(data, lines, rawText);
    }

    // ── Subtotal ──
    if (data.subtotal == 0) {
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.contains('sub total') || lower.contains('subtotal')) {
          final v = _extractDecimal(line);
          if (v > 0) { data.subtotal = v; break; }
        }
      }
    }

    // ── Tax ──
    if (data.tax == 0) {
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.contains('tax') || lower.contains('gst') || lower.contains('sst')) {
          final v = _extractDecimal(line);
          if (v > 0) { data.tax = v; break; }
        }
      }
    }
  }

  /// Extract total amount using Priority 3 strategy (Strategy C2):
  /// Priority 1: Find "TOTAL RM X.XX" or "Total X.XX" near anchor C match
  /// Priority 2: Find "Grand Total" or "Amount Due" label
  /// Priority 3: Find largest decimal value > RM 1.0 in bottom 30% of receipt
  void _extractTotalFromFullOcr(ReceiptData data, List<String> lines, String rawText) {
    final allLines = lines.toList();

    // ── Priority 1: TOTAL label line ──
    for (final line in allLines) {
      final lower = line.toLowerCase();
      // Must be a "TOTAL" labeled line (not "Total Item", "Total Qty")
      if (lower.contains('total') && !lower.contains('item') && !lower.contains('qty') &&
          !lower.contains('saving') && !lower.contains('discount')) {
        final v = _extractDecimal(line);
        if (v > 1.0) { data.amount = v; return; }
      }
    }

    // ── Priority 2: Grand Total / Amount Due / Total Payable ──
    for (final line in allLines) {
      final lower = line.toLowerCase();
      if (lower.contains('grand') || lower.contains('amount') ||
          (lower.contains('total') && lower.contains('payable'))) {
        final v = _extractDecimal(line);
        if (v > 1.0) { data.amount = v; return; }
      }
    }

    // ── Priority 3: Bottom 30% scan — largest decimal > RM 1.0 ──
    final scanStartIdx = (allLines.length * 0.7).round();
    double best = 0;
    for (int i = scanStartIdx; i < allLines.length; i++) {
      final line = allLines[i];
      final lower = line.toLowerCase();
      // Skip lines that are clearly not the total
      if (lower.contains('cash') || lower.contains('change') ||
          lower.contains('card') || lower.contains('payment')) continue;
      // Skip lines with item counts or quantities
      if (RegExp(r'\d+\s*[xX×]\s*\d+').hasMatch(line)) continue;

      final v = _extractDecimal(line);
      if (v > 1.0 && v < 100000 && v > best) best = v;
    }

    if (best > 0) { data.amount = best; return; }

    // ── Priority 4: Full receipt scan (last resort) ──
    for (final line in allLines.reversed) {
      final lower = line.toLowerCase();
      if (lower.contains('cash') || lower.contains('change')) continue;
      final v = _extractDecimal(line);
      if (v > 1.0 && v < 100000) { data.amount = v; return; }
    }
  }

  // ── Decimal extraction (supports RM, comma separators, Malaysian format) ──

  double _extractDecimal(String text) {
    // Pattern 1: RM followed by optional spaces and number (with optional comma separators)
    // e.g. "RM 372.45", "RM372.45", "RM 1,234.56"
    var m = RegExp(r'RM\s*([\d,]+\.?\d{0,2})', caseSensitive: false).firstMatch(text);
    if (m != null) {
      final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (parsed != null && parsed > 0) return parsed;
    }

    // Pattern 2: Number followed by RM suffix
    // e.g. "372.45 RM"
    m = RegExp(r'([\d,]+\.\d{2})\s*RM', caseSensitive: false).firstMatch(text);
    if (m != null) {
      final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (parsed != null && parsed > 0) return parsed;
    }

    // Pattern 3: Plain decimal with comma separators
    // e.g. "1,234.56" or "372.45"
    m = RegExp(r'\b([\d,]+\.\d{2})\b').firstMatch(text);
    if (m != null) {
      final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (parsed != null && parsed > 0) return parsed;
    }

    // Pattern 4: Number with comma separator and optional decimal
    // e.g. "1,234" → treat as integer
    m = RegExp(r'\b([\d,]+)\b').firstMatch(text);
    if (m != null) {
      final parsed = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (parsed != null && parsed > 0) return parsed;
    }

    return 0;
  }
}

import 'dart:ui';

/// Represents a configured ROI (Region of Interest) field on a receipt template.
class FieldROI {
  final String id;
  final String fieldName; // 'store_name', 'date', 'time', 'receipt_number', etc.
  final String displayLabel; // Human-readable label
  Rect roi; // Region of Interest [left, top, right, bottom]
  final String ocrEngine; // 'mlkit' | 'both'
  double confidenceThreshold;
  bool isRequired;
  String validationRule; // 'date', 'numeric', 'currency', 'text', 'none'
  String? customFieldName; // Only if fieldName == 'custom_field'

  FieldROI({
    required this.id,
    required this.fieldName,
    required this.displayLabel,
    required this.roi,
    this.ocrEngine = 'mlkit',
    this.confidenceThreshold = 0.6,
    this.isRequired = false,
    this.validationRule = 'text',
    this.customFieldName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fieldName': fieldName,
        'displayLabel': displayLabel,
        'roi_left': roi.left,
        'roi_top': roi.top,
        'roi_right': roi.right,
        'roi_bottom': roi.bottom,
        'ocrEngine': ocrEngine,
        'confidenceThreshold': confidenceThreshold,
        'isRequired': isRequired,
        'validationRule': validationRule,
        'customFieldName': customFieldName,
      };

  factory FieldROI.fromJson(Map<String, dynamic> json) => FieldROI(
        id: json['id'] as String,
        fieldName: json['fieldName'] as String,
        displayLabel: json['displayLabel'] as String,
        roi: Rect.fromLTRB(
          (json['roi_left'] as num).toDouble(),
          (json['roi_top'] as num).toDouble(),
          (json['roi_right'] as num).toDouble(),
          (json['roi_bottom'] as num).toDouble(),
        ),
        ocrEngine: json['ocrEngine'] as String? ?? 'mlkit',
        confidenceThreshold:
            (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.6,
        isRequired: json['isRequired'] as bool? ?? false,
        validationRule: json['validationRule'] as String? ?? 'text',
        customFieldName: json['customFieldName'] as String?,
      );

  static const List<Map<String, String>> availableFields = [
    {'name': 'store_name', 'label': 'Store Name'},
    {'name': 'date', 'label': 'Date'},
    {'name': 'time', 'label': 'Time'},
    {'name': 'receipt_number', 'label': 'Receipt Number'},
    {'name': 'cashier', 'label': 'Cashier'},
    {'name': 'terminal_id', 'label': 'Terminal ID'},
    {'name': 'currency', 'label': 'Currency'},
    {'name': 'item_table', 'label': 'Item Table'},
    {'name': 'quantity', 'label': 'Quantity'},
    {'name': 'item_description', 'label': 'Item Description'},
    {'name': 'unit_price', 'label': 'Unit Price'},
    {'name': 'discount', 'label': 'Discount'},
    {'name': 'tax', 'label': 'Tax'},
    {'name': 'service_charge', 'label': 'Service Charge'},
    {'name': 'subtotal', 'label': 'Subtotal'},
    {'name': 'total', 'label': 'Total'},
    {'name': 'payment_method', 'label': 'Payment Method'},
    {'name': 'membership_number', 'label': 'Membership Number'},
    {'name': 'custom_field', 'label': 'Custom Field'},
  ];
}

/// Column definitions for the dynamic item table
class ItemTableConfig {
  final String id;
  Rect tableRoi;
  Rect quantityColumn;
  Rect descriptionColumn;
  Rect unitPriceColumn;
  Rect discountColumn;
  Rect amountColumn;

  ItemTableConfig({
    required this.id,
    required this.tableRoi,
    required this.quantityColumn,
    required this.descriptionColumn,
    required this.unitPriceColumn,
    required this.discountColumn,
    required this.amountColumn,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableRoi_left': tableRoi.left,
        'tableRoi_top': tableRoi.top,
        'tableRoi_right': tableRoi.right,
        'tableRoi_bottom': tableRoi.bottom,
        'qty_left': quantityColumn.left,
        'qty_top': quantityColumn.top,
        'qty_right': quantityColumn.right,
        'qty_bottom': quantityColumn.bottom,
        'desc_left': descriptionColumn.left,
        'desc_top': descriptionColumn.top,
        'desc_right': descriptionColumn.right,
        'desc_bottom': descriptionColumn.bottom,
        'price_left': unitPriceColumn.left,
        'price_top': unitPriceColumn.top,
        'price_right': unitPriceColumn.right,
        'price_bottom': unitPriceColumn.bottom,
        'discount_left': discountColumn.left,
        'discount_top': discountColumn.top,
        'discount_right': discountColumn.right,
        'discount_bottom': discountColumn.bottom,
        'amount_left': amountColumn.left,
        'amount_top': amountColumn.top,
        'amount_right': amountColumn.right,
        'amount_bottom': amountColumn.bottom,
      };

  factory ItemTableConfig.fromJson(Map<String, dynamic> json) =>
      ItemTableConfig(
        id: json['id'] as String,
        tableRoi: Rect.fromLTRB(
          (json['tableRoi_left'] as num).toDouble(),
          (json['tableRoi_top'] as num).toDouble(),
          (json['tableRoi_right'] as num).toDouble(),
          (json['tableRoi_bottom'] as num).toDouble(),
        ),
        quantityColumn: Rect.fromLTRB(
          (json['qty_left'] as num).toDouble(),
          (json['qty_top'] as num).toDouble(),
          (json['qty_right'] as num).toDouble(),
          (json['qty_bottom'] as num).toDouble(),
        ),
        descriptionColumn: Rect.fromLTRB(
          (json['desc_left'] as num).toDouble(),
          (json['desc_top'] as num).toDouble(),
          (json['desc_right'] as num).toDouble(),
          (json['desc_bottom'] as num).toDouble(),
        ),
        unitPriceColumn: Rect.fromLTRB(
          (json['price_left'] as num).toDouble(),
          (json['price_top'] as num).toDouble(),
          (json['price_right'] as num).toDouble(),
          (json['price_bottom'] as num).toDouble(),
        ),
        discountColumn: Rect.fromLTRB(
          (json['discount_left'] as num).toDouble(),
          (json['discount_top'] as num).toDouble(),
          (json['discount_right'] as num).toDouble(),
          (json['discount_bottom'] as num).toDouble(),
        ),
        amountColumn: Rect.fromLTRB(
          (json['amount_left'] as num).toDouble(),
          (json['amount_top'] as num).toDouble(),
          (json['amount_right'] as num).toDouble(),
          (json['amount_bottom'] as num).toDouble(),
        ),
      );
}

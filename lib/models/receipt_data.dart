class ReceiptData {
  final String filename;
  String date;
  String time;
  String supplier;
  String number;
  double amount;
  String description;
  String category;
  String paymentMethod;
  double subtotal;
  double tax;
  String currency;
  String cashier;
  String terminalId;
  String membershipNumber;
  List<ItemRow> items;
  Map<String, String> customFields;
  double confidence;
  bool isValidated;

  ReceiptData({
    required this.filename,
    this.date = '',
    this.time = '',
    this.supplier = '',
    this.number = '',
    this.amount = 0.0,
    this.description = '',
    this.category = '',
    this.paymentMethod = '',
    this.subtotal = 0.0,
    this.tax = 0.0,
    this.currency = 'RM',
    this.cashier = '',
    this.terminalId = '',
    this.membershipNumber = '',
    List<ItemRow>? items,
    Map<String, String>? customFields,
    this.confidence = 0.0,
    this.isValidated = false,
  })  : items = items ?? [],
        customFields = customFields ?? {};

  List<dynamic> toExcelRow() {
    return [
      filename,
      date,
      time,
      supplier,
      number,
      amount,
      currency,
      paymentMethod,
      subtotal,
      tax,
      description,
      cashier,
      terminalId,
      membershipNumber,
      items.map((i) => i.toBriefString()).join('; '),
    ];
  }

  static List<String> get excelHeaders => [
        'Filename',
        'Date',
        'Time',
        'Supplier',
        'Receipt No',
        'Amount (RM)',
        'Currency',
        'Payment Method',
        'Subtotal',
        'Tax',
        'Description',
        'Cashier',
        'Terminal ID',
        'Membership No',
        'Items',
      ];
}

class ItemRow {
  int quantity;
  String description;
  double unitPrice;
  double discount;
  double amount;

  ItemRow({
    this.quantity = 1,
    this.description = '',
    this.unitPrice = 0.0,
    this.discount = 0.0,
    this.amount = 0.0,
  });

  String toBriefString() => '$description x$quantity RM${amount.toStringAsFixed(2)}';
}

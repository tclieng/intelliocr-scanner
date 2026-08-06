import 'dart:convert';
import 'anchor_point.dart';
import 'field_roi.dart';

/// Represents a complete supplier receipt template for the 3-Anchor system.
class ReceiptTemplate {
  final String id;
  String supplierName;
  int templateVersion;
  final DateTime createdAt;
  DateTime updatedAt;
  String? masterImagePath;

  // Three anchors
  AnchorPoint? anchorA; // Fixed header anchor A (logo/name)
  AnchorPoint? anchorB; // Fixed header anchor B (tax invoice/GST)
  AnchorPoint? anchorC; // Dynamic footer anchor (Total/Subtotal)

  // Configured ROI fields
  List<FieldROI> fields;

  // Item table configuration (legacy, deprecated)
  ItemTableConfig? itemTableConfig;

  // YELLOW Box configuration (new, replaces itemTableConfig)
  YellowBoxConfig? yellowBoxConfig;

  // Validation rules
  Map<String, String> validationRules;

  // Processing dimensions (original master receipt size)
  double masterWidth;
  double masterHeight;

  ReceiptTemplate({
    required this.id,
    required this.supplierName,
    this.templateVersion = 1,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.masterImagePath,
    this.anchorA,
    this.anchorB,
    this.anchorC,
    List<FieldROI>? fields,
    this.itemTableConfig,
    this.yellowBoxConfig,
    Map<String, String>? validationRules,
    this.masterWidth = 0,
    this.masterHeight = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        fields = fields ?? [],
        validationRules = validationRules ?? {};

  String get displayName => '$supplierName v$templateVersion';

  bool get isComplete =>
      anchorA != null && anchorB != null && anchorC != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierName': supplierName,
        'templateVersion': templateVersion,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'masterImagePath': masterImagePath,
        'masterWidth': masterWidth,
        'masterHeight': masterHeight,
        'anchorA': anchorA?.toJson(),
        'anchorB': anchorB?.toJson(),
        'anchorC': anchorC?.toJson(),
        'fields': fields.map((f) => f.toJson()).toList(),
        'itemTableConfig': itemTableConfig?.toJson(),
        'yellowBoxConfig': yellowBoxConfig?.toJson(),
        'validationRules': validationRules,
      };

  String toJsonString() => jsonEncode(toJson());

  factory ReceiptTemplate.fromJson(Map<String, dynamic> json) =>
      ReceiptTemplate(
        id: json['id'] as String,
        supplierName: json['supplierName'] as String,
        templateVersion: json['templateVersion'] as int? ?? 1,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        masterImagePath: json['masterImagePath'] as String?,
        masterWidth: (json['masterWidth'] as num?)?.toDouble() ?? 0,
        masterHeight: (json['masterHeight'] as num?)?.toDouble() ?? 0,
        anchorA: json['anchorA'] != null
            ? AnchorPoint.fromJson(json['anchorA'] as Map<String, dynamic>)
            : null,
        anchorB: json['anchorB'] != null
            ? AnchorPoint.fromJson(json['anchorB'] as Map<String, dynamic>)
            : null,
        anchorC: json['anchorC'] != null
            ? AnchorPoint.fromJson(json['anchorC'] as Map<String, dynamic>)
            : null,
        fields: (json['fields'] as List<dynamic>? ?? [])
            .map((f) => FieldROI.fromJson(f as Map<String, dynamic>))
            .toList(),
        itemTableConfig: json['itemTableConfig'] != null
            ? ItemTableConfig.fromJson(
                json['itemTableConfig'] as Map<String, dynamic>)
            : null,
        yellowBoxConfig: json['yellowBoxConfig'] != null
            ? YellowBoxConfig.fromJson(
                json['yellowBoxConfig'] as Map<String, dynamic>)
            : (json['itemTableConfig'] != null
                ? ItemTableConfig.fromJson(
                    json['itemTableConfig'] as Map<String, dynamic>).toYellowBoxConfig()
                : null), // Auto-migrate legacy itemTableConfig
        validationRules:
            (json['validationRules'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k, v as String)),
      );

  factory ReceiptTemplate.fromJsonString(String jsonString) =>
      ReceiptTemplate.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}

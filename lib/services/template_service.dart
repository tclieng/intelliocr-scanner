import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/receipt_template.dart';

/// Service for managing supplier receipt templates (CRUD).
class TemplateService {
  static final TemplateService _instance = TemplateService._();
  factory TemplateService() => _instance;
  TemplateService._();

  List<ReceiptTemplate> _templates = [];

  List<ReceiptTemplate> get templates => List.unmodifiable(_templates);

  Future<String> get _storagePath async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/templates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Load all saved templates from storage.
  Future<void> loadTemplates() async {
    final path = await _storagePath;
    final indexFile = File('$path/index.json');
    if (await indexFile.exists()) {
      final content = await indexFile.readAsString();
      final ids = List<String>.from(jsonDecode(content));
      _templates = [];
      for (final id in ids) {
        final tplFile = File('$path/$id.json');
        if (await tplFile.exists()) {
          final tpl = ReceiptTemplate.fromJsonString(
              await tplFile.readAsString());
          _templates.add(tpl);
        }
      }
    }
  }

  /// Save a template to persistent storage.
  Future<void> saveTemplate(ReceiptTemplate template) async {
    final path = await _storagePath;
    final tplFile = File('$path/${template.id}.json');
    await tplFile.writeAsString(template.toJsonString());

    // Update index
    if (!_templates.any((t) => t.id == template.id)) {
      _templates.add(template);
    } else {
      final idx = _templates.indexWhere((t) => t.id == template.id);
      _templates[idx] = template;
    }
    await _saveIndex(path);
  }

  /// Delete a template by ID.
  Future<void> deleteTemplate(String id) async {
    final path = await _storagePath;
    final tplFile = File('$path/$id.json');
    if (await tplFile.exists()) await tplFile.delete();
    _templates.removeWhere((t) => t.id == id);
    await _saveIndex(path);
  }

  /// Find a matching template by supplier name or header text.
  ReceiptTemplate? findTemplateBySupplier(String supplierName) {
    final name = supplierName.toLowerCase();
    for (final tpl in _templates) {
      if (tpl.supplierName.toLowerCase().contains(name)) return tpl;
      if (tpl.anchorA != null &&
          tpl.anchorA!.expectedText.toLowerCase().contains(name)) return tpl;
    }
    return null;
  }

  /// Get a template by ID.
  ReceiptTemplate? getTemplate(String id) {
    try {
      return _templates.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  int get templateCount => _templates.length;

  Future<void> _saveIndex(String path) async {
    final indexFile = File('$path/index.json');
    await indexFile.writeAsString(
        jsonEncode(_templates.map((t) => t.id).toList()));
  }

  /// Copy a master template image to app storage.
  Future<String?> saveMasterImage(String templateId, File sourceImage) async {
    final path = await _storagePath;
    final destDir = Directory('$path/images');
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final destFile = File('${destDir.path}/${templateId}_master.jpg');
    await sourceImage.copy(destFile.path);
    return destFile.path;
  }
}

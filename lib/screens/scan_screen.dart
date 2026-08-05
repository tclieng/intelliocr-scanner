import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../models/receipt_template.dart';
import '../models/receipt_data.dart';
import '../services/match_engine.dart';
import '../services/template_service.dart';
import '../services/excel_service.dart';
import '../services/image_processor.dart';

/// Phase 2: Template-matched receipt scanning screen.
class ScanScreen extends StatefulWidget {
  final ReceiptTemplate? preselectedTemplate;
  const ScanScreen({super.key, this.preselectedTemplate});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final TemplateService _templateService = TemplateService();
  final MatchEngine _matchEngine = MatchEngine();
  final ExcelService _excel = ExcelService();
  final ImagePicker _picker = ImagePicker();

  List<ReceiptTemplate> _templates = [];
  ReceiptTemplate? _selectedTemplate;
  Uint8List? _previewBytes;
  final List<ReceiptData> _results = [];
  ReceiptData? _currentResult;
  bool _processing = false;
  bool _matched = false;
  double _confidence = 0;
  String _status = 'Select a template and capture';

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.preselectedTemplate;
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    await _templateService.loadTemplates();
    setState(() {
      _templates = _templateService.templates;
      if (_selectedTemplate == null && _templates.isNotEmpty) {
        _selectedTemplate = _templates.first;
      }
    });
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _captureAndProcess() async {
    if (_selectedTemplate == null) {
      _showSnack('Select a template first');
      return;
    }
    try {
      final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85);
      if (photo == null) return;
      await _processImage(File(photo.path));
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _pickAndProcess() async {
    if (_selectedTemplate == null) {
      _showSnack('Select a template first');
      return;
    }
    try {
      final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85);
      if (image == null) return;
      await _processImage(File(image.path));
    } catch (e) {
      _showSnack(e.toString());
    }
  }

  Future<void> _processImage(File imageFile) async {
    setState(() {
      _processing = true;
      _status = 'Preprocessing...';
      _previewBytes = null;
      _results.clear();
      _currentResult = null;
      _matched = false;
      _confidence = 0;
    });

    try {
      setState(() => _status = 'Preprocessing...');
      final bytes = await imageFile.readAsBytes();
      final processedBytes = await ImageProcessor.processReceipt(bytes);

      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('Failed to decode image');
      final capturedWidth = decoded.width.toDouble();
      final capturedHeight = decoded.height.toDouble();

      final tempFile = File(
          '${imageFile.parent.path}/iocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(processedBytes);

      setState(() => _previewBytes = processedBytes);
      setState(
          () => _status = 'Matching "${_selectedTemplate!.supplierName}"...');

      final result = await _matchEngine.extractWithTemplate(
        _selectedTemplate!,
        tempFile,
        capturedWidth,
        capturedHeight,
        imageFile.uri.pathSegments.last,
      );

      _results.add(result);
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}

      setState(() {
        _currentResult = result;
        _matched = result.isValidated;
        _confidence = result.confidence;
        _status = result.isValidated
            ? 'Matched! ${(_confidence * 100).toStringAsFixed(0)}%'
            : 'Low match - fallback OCR';
      });
    } catch (e) {
      _status = 'Error: $e';
      _showSnack('Failed: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _exportExcel() async {
    final receipts = _results.isNotEmpty
        ? _results
        : (_currentResult != null ? [_currentResult!] : null);
    if (receipts == null || receipts.isEmpty) return;
    setState(() => _status = 'Generating Excel...');
    try {
      final s = _selectedTemplate?.supplierName ?? 'Receipts';
      final path = await _excel.createExcel(receipts, s);
      setState(() => _status = 'Opening share...');
      await _excel.shareViaGmailWithAttachment(path, s);
      setState(() => _status = 'Done!');
    } catch (e) {
      _status = 'Export error: $e';
      _showSnack('Export failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF6B35),
      appBar: AppBar(
        title: const Text('IntelliOCR Scanner',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF6B35), Color(0xFFE85D2C)],
        )),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(_status,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textAlign: TextAlign.center),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTemplateSelector(),
          const SizedBox(height: 12),
          if (_previewBytes != null) ...[
            _buildPreviewSection(),
            const SizedBox(height: 12),
          ],
          if (_currentResult != null) ...[
            _buildResultCard(),
            const SizedBox(height: 12),
          ],
          if (_results.length > 1) ...[
            _buildBatchCount(),
            const SizedBox(height: 12),
          ],
          _buildActionButtons(),
          if (_matched || _confidence > 0) ...[
            const SizedBox(height: 12),
            _buildConfidenceBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bookmark, size: 18, color: Color(0xFFFF6B35)),
            const SizedBox(width: 6),
            const Text('Template',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            TextButton(
                onPressed: _loadTemplates,
                child: const Text('Refresh', style: TextStyle(fontSize: 12))),
          ],
        ),
        const SizedBox(height: 6),
        if (_templates.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                    child: Text('No templates found. Create one first.',
                        style: TextStyle(fontSize: 12, color: Colors.orange))),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButton<ReceiptTemplate>(
              value: _selectedTemplate,
              isExpanded: true,
              underline: const SizedBox(),
              items: _templates.map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.isComplete ? Icons.check_circle : Icons.warning_amber,
                          size: 16,
                          color: t.isComplete ? Colors.green : Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t.supplierName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14))),
                      if (t.isComplete)
                        Text('${t.fields.length} fields',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (t) => setState(() => _selectedTemplate = t),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.image, size: 18, color: Color(0xFFFF6B35)),
            const SizedBox(width: 6),
            const Text('Captured',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 8),
            if (_matched)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Matched',
                    style:
                        TextStyle(fontSize: 11, color: Colors.green.shade700)),
              )
            else if (_confidence > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(_confidence * 100).toStringAsFixed(0)}% match',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange.shade800),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_previewBytes!,
              width: double.infinity, fit: BoxFit.contain),
        ),
      ],
    );
  }

  Widget _buildResultCard() {
    final r = _currentResult!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _matched ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _matched ? Colors.green.shade200 : Colors.orange.shade200,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_matched ? Icons.check_circle : Icons.info_outline,
                  color: _matched ? Colors.green : Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.supplier.isNotEmpty ? r.supplier : 'Receipt',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'RM ${r.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
              '${r.date.isNotEmpty ? r.date : '-'}  #${r.number.isNotEmpty ? r.number : '-'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (r.paymentMethod.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Payment: ${r.paymentMethod}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          if (r.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('${r.items.length} item(s):',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            ...r.items.take(5).map((item) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(item.description,
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Text('x${item.quantity}  RM ${item.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                )),
            if (r.items.length > 5)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('... and ${r.items.length - 5} more',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic)),
              ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Confidence: ${(r.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              if (r.items.isNotEmpty)
                Text(
                    'Subtotal: RM ${r.subtotal.toStringAsFixed(2)}  Tax: RM ${r.tax.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBatchCount() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open,
              color: Color(0xFFFF6B35), size: 20),
          const SizedBox(width: 8),
          Text('${_results.length} receipt(s)',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Color(0xFFFF6B35))),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _captureAndProcess,
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('Capture'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _processing ? null : _pickAndProcess,
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        if (_results.isNotEmpty || _currentResult != null) ...[
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _exportExcel,
            icon: const Icon(Icons.email, size: 20),
            label: Text(_results.length > 1 ? 'Export ${_results.length}' : 'Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE85D2C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfidenceBar() {
    final pct = _confidence.clamp(0.0, 1.0);
    final color = pct >= 0.7
        ? Colors.green
        : pct >= 0.4
            ? Colors.orange
            : Colors.red;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.analytics, size: 16, color: Color(0xFFFF6B35)),
            const SizedBox(width: 4),
            Text('Confidence: ${(pct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          pct >= 0.7
              ? 'Template matched - ROI extraction'
              : pct >= 0.4
                  ? 'Partial match - hybrid'
                  : 'Low match - fallback OCR',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

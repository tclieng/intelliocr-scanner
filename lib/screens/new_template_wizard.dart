import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../services/template_service.dart';
import '../services/image_processor.dart';
import '../models/receipt_template.dart';
import '../models/anchor_point.dart';
import '../models/field_roi.dart';

/// New Template Wizard — 4 Steps
/// Step 1: Capture Master Receipt
/// Step 2: Draw 4 Boxes (RED, BLUE, YELLOW, GREEN)
/// Step 3: Define Columns in YELLOW Box
/// Step 4: Save Template
class NewTemplateWizard extends StatefulWidget {
  const NewTemplateWizard({super.key});

  @override
  State<NewTemplateWizard> createState() => _NewTemplateWizardState();
}

class _NewTemplateWizardState extends State<NewTemplateWizard> {
  final TemplateService _templateService = TemplateService();
  final ImagePicker _picker = ImagePicker();

  // Wizard state
  int _currentStep = 0;
  late ReceiptTemplate _template;
  File? _masterImage;
  img.Image? _processedImage;

  // Four boxes state (Step 2)
  Rect _redBox = Rect.zero;    // RED: Company Name (Anchor A)
  Rect _blueBox = Rect.zero;   // BLUE: Date (Anchor B)
  Rect _yellowBox = Rect.zero; // YELLOW: Items (ROI Fields)
  Rect _greenBox = Rect.zero;   // GREEN: Total (Anchor C)
  String _redExpectedText = '';

  // Column definitions (Step 3)
  List<_ColumnLine> _verticalLines = [];
  String _supplierName = '';

  @override
  void initState() {
    super.initState();
    final id = 'TPL_${DateTime.now().millisecondsSinceEpoch}';
    _template = ReceiptTemplate(id: id, supplierName: '');
  }

  // ── Navigation ──

  void _nextStep() {
    if (_currentStep < 3) setState(() => _currentStep++);
  }

  void _prevStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0: return _masterImage != null;
      case 1: return _redBox != Rect.zero && _blueBox != Rect.zero &&
                    _yellowBox != Rect.zero && _greenBox != Rect.zero;
      case 2: return _linesCount >= 2; // At least 2 vertical lines = 1 column
      case 3: return _canSave; // All boxes set, lines defined, name entered
      default: return false;
    }
  }

  int get _linesCount => _verticalLines.where((l) => l.isVertical).length;

  bool get _canSave =>
      _masterImage != null &&
      _redBox != Rect.zero &&
      _blueBox != Rect.zero &&
      _yellowBox != Rect.zero &&
      _greenBox != Rect.zero &&
      _linesCount >= 2 &&
      _redExpectedText.trim().isNotEmpty;

  // ── Step 1: Capture Master Receipt ──

  Future<void> _captureMaster() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (photo == null) return;

    final bytes = await File(photo.path).readAsBytes();
    final processedBytes = await ImageProcessor.processReceipt(bytes);

    _masterImage = File(photo.path.replaceAll('.jpg', '_master.jpg'));
    await _masterImage!.writeAsBytes(processedBytes);
    _processedImage = img.decodeImage(processedBytes);

    if (_processedImage != null) {
      _template.masterWidth = _processedImage!.width.toDouble();
      _template.masterHeight = _processedImage!.height.toDouble();
      _initializeBoxes();
    }
    setState(() {});
  }

  Future<void> _pickMasterFromGallery() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final bytes = await File(image.path).readAsBytes();
    final processedBytes = await ImageProcessor.processReceipt(bytes);

    _masterImage = File(image.path.replaceAll('.jpg', '_master.jpg'));
    await _masterImage!.writeAsBytes(processedBytes);
    _processedImage = img.decodeImage(processedBytes);

    if (_processedImage != null) {
      _template.masterWidth = _processedImage!.width.toDouble();
      _template.masterHeight = _processedImage!.height.toDouble();
      _initializeBoxes();
    }
    setState(() {});
  }

  void _initializeBoxes() {
    if (_processedImage == null) return;
    
    final w = _processedImage!.width.toDouble();
    final h = _processedImage!.height.toDouble();
    
    // Initialize boxes in top-to-bottom sequence, kept within receipt bounds
    _redBox = Rect.fromLTWH(w * 0.10, h * 0.04, w * 0.80, h * 0.07);   // Company name (top)
    _blueBox = Rect.fromLTWH(w * 0.10, h * 0.14, w * 0.80, h * 0.05);  // Date (below red)
    _yellowBox = Rect.fromLTWH(w * 0.08, h * 0.30, w * 0.84, h * 0.40); // Items (middle, ~30%-70%)
    _greenBox = Rect.fromLTWH(w * 0.30, h * 0.82, w * 0.50, h * 0.07);  // Total (bottom)
  }

  void _rotateMaster(int degrees) {
    if (_processedImage == null) return;
    setState(() {
      _processedImage = img.copyRotate(_processedImage!, angle: degrees);
      final bytes = img.encodeJpg(_processedImage!, quality: 92);
      _masterImage?.writeAsBytes(bytes);
      _template.masterWidth = _processedImage!.width.toDouble();
      _template.masterHeight = _processedImage!.height.toDouble();
      
      // Reinitialize boxes for new dimensions
      _initializeBoxes();
    });
  }

  // ── Step 2: Draw 4 Boxes ──

  Future<void> _openFourBoxEditor() async {
    if (_processedImage == null) return;

    final result = await Navigator.of(context).push<_FourBoxResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FourBoxEditorScreen(
          image: _processedImage!,
          initialRed: _redBox,
          initialBlue: _blueBox,
          initialYellow: _yellowBox,
          initialGreen: _greenBox,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _redBox = result.red;
      _blueBox = result.blue;
      _yellowBox = result.yellow;
      _greenBox = result.green;
      _redExpectedText = result.redExpectedText;
      
      // Update template anchors
      _template.anchorA = AnchorPoint(
        id: 'anchor_a',
        label: 'Company Name',
        type: 'header_a',
        roi: _redBox,
        expectedText: _redExpectedText,
        position: (_redBox.top + _redBox.bottom) / 2 / _template.masterHeight,
      );
      
      _template.anchorB = AnchorPoint(
        id: 'anchor_b',
        label: 'Date',
        type: 'header_b',
        roi: _blueBox,
        expectedText: '',
        position: (_blueBox.top + _blueBox.bottom) / 2 / _template.masterHeight,
      );
      
      _template.anchorC = AnchorPoint(
        id: 'anchor_c',
        label: 'Total',
        type: 'footer_c',
        roi: _greenBox,
        expectedText: '',
        position: (_greenBox.top + _greenBox.bottom) / 2 / _template.masterHeight,
      );
      
      _template.yellowBoxConfig = YellowBoxConfig(
        id: 'yellow_${DateTime.now().millisecondsSinceEpoch}',
        roi: _yellowBox,
        columns: [],
      );
      
      // Initialize vertical lines for Step 3
      _initializeVerticalLines();
    });
  }

  void _initializeVerticalLines() {
    if (_yellowBox == Rect.zero) return;
    
    final yw = _yellowBox.width;
    _verticalLines = [
      _ColumnLine(id: 'v0', x: 0, isVertical: true),              // Left edge
      _ColumnLine(id: 'v1', x: yw * 0.45, isVertical: true),     // After desc
      _ColumnLine(id: 'v2', x: yw * 0.55, isVertical: true),      // After qty
      _ColumnLine(id: 'v3', x: yw * 0.70, isVertical: true),     // After price
      _ColumnLine(id: 'v4', x: yw * 0.80, isVertical: true),     // After disc
      _ColumnLine(id: 'v5', x: yw, isVertical: true),            // Right edge
    ];
  }

  // ── Step 3: Define Columns ──

  Future<void> _openColumnEditor() async {
    if (_yellowBox == Rect.zero) return;

    final result = await Navigator.of(context).push<List<_ColumnLine>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ColumnEditorScreen(
          image: _processedImage!,
          yellowBox: _yellowBox,
          initialLines: _verticalLines,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      _verticalLines = result;
    });
  }

  void _defineColumns() {
    // Create YellowBoxConfig with defined columns
    final columns = <YellowBoxColumn>[];
    final sortedLines = _verticalLines.where((l) => l.isVertical).toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    for (int i = 0; i < sortedLines.length - 1; i++) {
      final left = sortedLines[i].x;
      final right = sortedLines[i + 1].x;
      final width = right - left;

      String name = 'item_description';
      String displayName = 'Item';

      // Determine column type based on position
      if (i == 0) {
        name = 'item_description';
        displayName = 'Item Description';
      } else if (i == sortedLines.length - 2) {
        name = 'amount';
        displayName = 'Amount';
      } else {
        // Middle columns - user can define later
        name = 'column_$i';
        displayName = 'Column $i';
      }

      columns.add(YellowBoxColumn(
        id: 'col_$i',
        name: name,
        displayName: displayName,
        x: left,
        width: width,
        order: i,
      ));
    }

    _template.yellowBoxConfig = YellowBoxConfig(
      id: 'yellow_${DateTime.now().millisecondsSinceEpoch}',
      roi: _yellowBox,
      columns: columns,
      detectRowsBySubtotal: true,
    );
  }

  // ── Step 4: Save ──

  void _showSaveDialog() {
    final nameController = TextEditingController(text: _redExpectedText);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter supplier name:'),
            const SizedBox(height: 8),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                hintText: 'e.g. ST ROSYAM MART',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter supplier name')),
                );
                return;
              }
              
              Navigator.of(ctx).pop();
              await _saveTemplate(name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTemplate(String supplierName) async {
    _defineColumns();
    
    _template.supplierName = supplierName;
    _template.updatedAt = DateTime.now();
    
    // Save master image
    if (_masterImage != null) {
      final imagePath = await _templateService.saveMasterImage(_template.id, _masterImage!);
      _template.masterImagePath = imagePath;
    }

    // Save template JSON
    await _templateService.saveTemplate(_template);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template "$supplierName" saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }

  // ── Build UI ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Template ${_currentStep + 1}/4'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Progress indicator
          LinearProgressIndicator(
            value: (_currentStep + 1) / 4,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
          ),
          
          // Step content
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
                _buildStep4(),
              ],
            ),
          ),
          
          // Navigation buttons
          _buildNavigation(),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Capture Master Receipt',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 12),
          Text(
            'Take a clear, well-lit photo of a sample receipt from this supplier.\n'
            'This will be used as the master template.',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _captureMaster,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMasterFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('From Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFF6B35)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),

          if (_processedImage != null) ...[
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final imgW = _processedImage!.width.toDouble();
                final imgH = _processedImage!.height.toDouble();
                final maxH = 400.0;
                final h = (constraints.maxWidth * imgH / imgW).clamp(200.0, maxH);
                return Container(
                  width: double.infinity,
                  height: h,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      img.encodeJpg(_processedImage!, quality: 85),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _rotateMaster(-90),
                  icon: const Icon(Icons.rotate_left),
                  label: const Text('Rotate Left'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: () => _rotateMaster(90),
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate Right'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2: Draw 4 Boxes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 12),
          Text(
            'Create 4 boxes on the receipt image. They must NOT overlap and should be arranged from top to bottom:\n\n'
            '🔴 RED: Company Name\n'
            '🔵 BLUE: Date of Purchase\n'
            '🟡 YELLOW: Purchase Items (ROI Fields)\n'
            '🟢 GREEN: Total Amount',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          
          // Preview with boxes
          if (_processedImage != null) ...[
            Container(
              width: double.infinity,
              height: 450,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildBoxPreview(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          Center(
            child: ElevatedButton.icon(
              onPressed: _openFourBoxEditor,
              icon: const Icon(Icons.edit),
              label: const Text('Open Box Editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxPreview() {
    if (_processedImage == null) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = _processedImage!.width.toDouble();
        final imgH = _processedImage!.height.toDouble();
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        if (imgW == 0 || imgH == 0) return const SizedBox();

        // BoxFit.contain math
        final scaleW = maxW / imgW;
        final scaleH = maxH / imgH;
        final scale = scaleW < scaleH ? scaleW : scaleH;
        final displayedW = imgW * scale;
        final displayedH = imgH * scale;
        final offsetX = (maxW - displayedW) / 2;
        final offsetY = (maxH - displayedH) / 2;

        return Stack(
          children: [
            // Image (filled to displayed rect so coords match)
            Positioned(
              left: offsetX,
              top: offsetY,
              width: displayedW,
              height: displayedH,
              child: Image.memory(
                img.encodeJpg(_processedImage!, quality: 85),
                fit: BoxFit.fill,
              ),
            ),

            // RED Box
            if (_redBox != Rect.zero)
              Positioned(
                left: offsetX + _redBox.left * scale,
                top: offsetY + _redBox.top * scale,
                width: _redBox.width * scale,
                height: _redBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                    color: Colors.red.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('RED', style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

            // BLUE Box
            if (_blueBox != Rect.zero)
              Positioned(
                left: offsetX + _blueBox.left * scale,
                top: offsetY + _blueBox.top * scale,
                width: _blueBox.width * scale,
                height: _blueBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 2),
                    color: Colors.blue.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('BLUE', style: TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

            // YELLOW Box
            if (_yellowBox != Rect.zero)
              Positioned(
                left: offsetX + _yellowBox.left * scale,
                top: offsetY + _yellowBox.top * scale,
                width: _yellowBox.width * scale,
                height: _yellowBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellow[700]!, width: 2),
                    color: Colors.yellow.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('YELLOW', style: TextStyle(fontSize: 14, color: Colors.brown, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),

            // GREEN Box
            if (_greenBox != Rect.zero)
              Positioned(
                left: offsetX + _greenBox.left * scale,
                top: offsetY + _greenBox.top * scale,
                width: _greenBox.width * scale,
                height: _greenBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 2),
                    color: Colors.green.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('GREEN', style: TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 3: Define Columns',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 12),
          Text(
            'Draw vertical lines inside the YELLOW box to define column boundaries.\n'
            'This helps extract data from purchase items correctly.\n\n'
            'Common columns: Item Description, Qty, Unit Price, Discount, Amount',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          const SizedBox(height: 24),
          
          if (_yellowBox != Rect.zero) ...[
            Container(
              width: double.infinity,
              height: 450,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildColumnPreview(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          Center(
            child: ElevatedButton.icon(
              onPressed: _openColumnEditor,
              icon: const Icon(Icons.grid_on),
              label: const Text('Open Column Editor'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnPreview() {
    if (_processedImage == null || _yellowBox == Rect.zero) return const SizedBox();

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgW = _processedImage!.width.toDouble();
        final imgH = _processedImage!.height.toDouble();
        final scale = constraints.maxWidth / imgW;
        
        // Calculate YELLOW box position relative to image
        final yellowLeft = _yellowBox.left * scale;
        final yellowTop = _yellowBox.top * scale;
        final yellowW = _yellowBox.width * scale;
        final yellowH = _yellowBox.height * scale;

        return Stack(
          children: [
            // Image
            Positioned.fill(
              child: Image.memory(
                img.encodeJpg(_processedImage!, quality: 85),
                fit: BoxFit.contain,
              ),
            ),
            
            // YELLOW box highlight
            Positioned(
              left: yellowLeft,
              top: yellowTop,
              width: yellowW,
              height: yellowH,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.yellow[700]!, width: 3),
                  color: Colors.yellow.withOpacity(0.2),
                ),
              ),
            ),
            
            // Vertical lines
            ..._verticalLines.where((l) => l.isVertical).map((line) {
              final x = yellowLeft + line.x * scale;
              return Positioned(
                left: x,
                top: yellowTop,
                child: Container(
                  width: 2,
                  height: yellowH,
                  color: Colors.purple,
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 4: Save Template',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 24),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Template Summary',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildSummaryRow('🔴 Company Name Box', _redBox != Rect.zero ? '✓ Set' : '✗ Not set'),
                  _buildSummaryRow('🔵 Date Box', _blueBox != Rect.zero ? '✓ Set' : '✗ Not set'),
                  _buildSummaryRow('🟡 Item Columns', '${_verticalLines.length - 1} columns defined'),
                  _buildSummaryRow('🟢 Total Box', _greenBox != Rect.zero ? '✓ Set' : '✗ Not set'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showSaveDialog,
              icon: const Icon(Icons.save),
              label: const Text('Save Template'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _canSave ? Colors.green : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (!_canSave)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⚠ Complete all steps: capture image, set 4 boxes, add ≥2 vertical lines, enter company name',
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildNavigation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            OutlinedButton(
              onPressed: _prevStep,
              child: const Text('← Back'),
            ),
          const Spacer(),
          if (_currentStep < 3)
            ElevatedButton(
              onPressed: _canProceed ? _nextStep : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
              child: const Text('Next →'),
            ),
        ],
      ),
    );
  }
}

// ── Helper Classes ──

class _FourBoxResult {
  final Rect red;
  final Rect blue;
  final Rect yellow;
  final Rect green;
  final String redExpectedText;

  _FourBoxResult({
    required this.red,
    required this.blue,
    required this.yellow,
    required this.green,
    required this.redExpectedText,
  });
}

class _ColumnLine {
  final String id;
  double x;  // For vertical: x position. For horizontal: y position
  bool isVertical;

  _ColumnLine({
    required this.id,
    required this.x,
    required this.isVertical,
  });
}

// ── Four Box Editor Screen ──

class _FourBoxEditorScreen extends StatefulWidget {
  final img.Image image;
  final Rect initialRed;
  final Rect initialBlue;
  final Rect initialYellow;
  final Rect initialGreen;

  const _FourBoxEditorScreen({
    required this.image,
    required this.initialRed,
    required this.initialBlue,
    required this.initialYellow,
    required this.initialGreen,
  });

  @override
  State<_FourBoxEditorScreen> createState() => _FourBoxEditorScreenState();
}

class _FourBoxEditorScreenState extends State<_FourBoxEditorScreen> {
  late Rect _red;
  late Rect _blue;
  late Rect _yellow;
  late Rect _green;
  String? _selectedBox;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _red = widget.initialRed;
    _blue = widget.initialBlue;
    _yellow = widget.initialYellow;
    _green = widget.initialGreen;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Helper: get the actual displayed image rect given a Stack's box constraints
  // Returns the rect (in widget coords) where the image is drawn (with BoxFit.contain)
  Rect _getDisplayedImageRect(double maxW, double maxH) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    if (imgW == 0 || imgH == 0) return Rect.fromLTWH(0, 0, maxW, maxH);

    final scaleW = maxW / imgW;
    final scaleH = maxH / imgH;
    final scale = scaleW < scaleH ? scaleW : scaleH;

    final displayedW = imgW * scale;
    final displayedH = imgH * scale;
    final offsetX = (maxW - displayedW) / 2;
    final offsetY = (maxH - displayedH) / 2;

    return Rect.fromLTWH(offsetX, offsetY, displayedW, displayedH);
  }

  // Convert image pixel coords to widget coords using displayed image rect
  Rect _imgToWidget(Rect imgRect, Rect displayedImgRect) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    if (imgW == 0 || imgH == 0) return displayedImgRect;

    final scaleX = displayedImgRect.width / imgW;
    final scaleY = displayedImgRect.height / imgH;

    return Rect.fromLTWH(
      displayedImgRect.left + imgRect.left * scaleX,
      displayedImgRect.top + imgRect.top * scaleY,
      imgRect.width * scaleX,
      imgRect.height * scaleY,
    );
  }

  // Convert widget coords to image pixel coords
  Rect _widgetToImg(Rect widgetRect, Rect displayedImgRect) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    if (imgW == 0 || imgH == 0) return widgetRect;

    final scaleX = imgW / displayedImgRect.width;
    final scaleY = imgH / displayedImgRect.height;

    return Rect.fromLTWH(
      (widgetRect.left - displayedImgRect.left) * scaleX,
      (widgetRect.top - displayedImgRect.top) * scaleY,
      widgetRect.width * scaleX,
      widgetRect.height * scaleY,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw 4 Boxes'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.orange[50],
            child: const Text(
              'Tap a box to select, drag to move. Use handles to resize.\n'
              'Top→Bottom: RED company, BLUE date, YELLOW items, GREEN total.\n'
              'Boxes must NOT overlap and stay within the receipt.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ),

          // Editor
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final displayedImg = _getDisplayedImageRect(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  onTapDown: (details) => _onTapDown(details.localPosition, displayedImg),
                  child: Stack(
                    children: [
                      // Background fill (for tap-outside detection)
                      Positioned.fill(
                        child: Container(color: Colors.black),
                      ),
                      // Image (clipped to displayed rect)
                      Positioned(
                        left: displayedImg.left,
                        top: displayedImg.top,
                        width: displayedImg.width,
                        height: displayedImg.height,
                        child: Image.memory(
                          img.encodeJpg(widget.image, quality: 85),
                          fit: BoxFit.fill,
                        ),
                      ),
                      // Boxes
                      _buildBox('red', _red, displayedImg, Colors.red),
                      _buildBox('blue', _blue, displayedImg, Colors.blue),
                      _buildBox('yellow', _yellow, displayedImg, Colors.yellow[700]!),
                      _buildBox('green', _green, displayedImg, Colors.green),
                    ],
                  ),
                );
              },
            ),
          ),

          // RED box text input
          if (_selectedBox == 'red')
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: TextField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Company Name (for template matching)',
                  hintText: 'e.g. ST ROSYAM MART',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBox(String id, Rect imgRect, Rect displayedImg, Color color) {
    if (imgRect == Rect.zero) return const SizedBox();

    final widgetRect = _imgToWidget(imgRect, displayedImg);
    final isSelected = _selectedBox == id;

    // Extend the hit area 14px on every side so taps just outside the box
    // still grab it. The colored visible box stays at the original size.
    const double kGrabMargin = 14;

    return Positioned(
      left: widgetRect.left - kGrabMargin,
      top: widgetRect.top - kGrabMargin,
      width: widgetRect.width + kGrabMargin * 2,
      height: widgetRect.height + kGrabMargin * 2,
      // Listener for instant touch response (lower latency than GestureDetector)
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _selectBox(id),
        onPointerMove: (event) {
          if (event.buttons & 1 != 0) {
            // Button down = drag
            _moveBox(id, event.delta, displayedImg);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Transparent grab ring (margin area) — keeps hit area big
            // without changing the visible box.
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.transparent),
              ),
            ),
            // Visible box
            Positioned(
              left: kGrabMargin,
              top: kGrabMargin,
              width: widgetRect.width,
              height: widgetRect.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? color : color.withOpacity(0.7),
                    width: isSelected ? 3 : 2,
                  ),
                  color: color.withOpacity(isSelected ? 0.20 : 0.15),
                ),
          child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Label
                    Positioned(
                      left: 4,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          id.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // Resize handles (always visible for easier access)
                    Positioned(
                      left: -22,
                      top: -22,
                      child: _buildHandle(color, 'tl', id, displayedImg),
                    ),
                    Positioned(
                      right: -22,
                      top: -22,
                      child: _buildHandle(color, 'tr', id, displayedImg),
                    ),
                    Positioned(
                      left: -22,
                      bottom: -22,
                      child: _buildHandle(color, 'bl', id, displayedImg),
                    ),
                    Positioned(
                      right: -22,
                      bottom: -22,
                      child: _buildHandle(color, 'br', id, displayedImg),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(Color color, String corner, String boxId, Rect displayedImg) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerMove: (event) {
        if (event.buttons & 1 != 0) {
          _resizeBox(boxId, corner, event.delta, displayedImg);
        }
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          corner == 'tl' ? Icons.north_west
              : corner == 'tr' ? Icons.north_east
              : corner == 'bl' ? Icons.south_west
              : Icons.south_east,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }

  void _onTapDown(Offset position, Rect displayedImg) {
    // Check which box was tapped (in widget coords)
    if (_containsPointWidget(_red, position, displayedImg)) {
      _selectBox('red');
    } else if (_containsPointWidget(_blue, position, displayedImg)) {
      _selectBox('blue');
    } else if (_containsPointWidget(_yellow, position, displayedImg)) {
      _selectBox('yellow');
    } else if (_containsPointWidget(_green, position, displayedImg)) {
      _selectBox('green');
    } else {
      setState(() => _selectedBox = null);
    }
  }

  bool _containsPointWidget(Rect imgRect, Offset point, Rect displayedImg) {
    if (imgRect == Rect.zero) return false;
    final w = _imgToWidget(imgRect, displayedImg);
    return point.dx >= w.left &&
        point.dx <= w.right &&
        point.dy >= w.top &&
        point.dy <= w.bottom;
  }

  void _selectBox(String id) {
    setState(() => _selectedBox = id);
  }

  void _moveBox(String id, Offset delta, Rect displayedImg) {
    setState(() {
      switch (id) {
        case 'red':
          _red = _shiftImgRect(_red, delta, displayedImg);
          break;
        case 'blue':
          _blue = _shiftImgRect(_blue, delta, displayedImg);
          break;
        case 'yellow':
          _yellow = _shiftImgRect(_yellow, delta, displayedImg);
          break;
        case 'green':
          _green = _shiftImgRect(_green, delta, displayedImg);
          break;
      }
    });
  }

  void _resizeBox(String id, String corner, Offset delta, Rect displayedImg) {
    setState(() {
      final scaleX = widget.image.width / displayedImg.width;
      final scaleY = widget.image.height / displayedImg.height;
      final dx = delta.dx * scaleX;
      final dy = delta.dy * scaleY;
      Rect current;
      switch (id) {
        case 'red': current = _red; break;
        case 'blue': current = _blue; break;
        case 'yellow': current = _yellow; break;
        case 'green': current = _green; break;
        default: return;
      }

      double newLeft = current.left;
      double newTop = current.top;
      double newRight = current.right;
      double newBottom = current.bottom;

      if (corner.contains('l')) {
        newLeft = (newLeft + dx).clamp(0.0, current.right - 30);
      }
      if (corner.contains('r')) {
        newRight = (newRight + dx).clamp(current.left + 30, widget.image.width.toDouble());
      }
      if (corner.contains('t')) {
        newTop = (newTop + dy).clamp(0.0, current.bottom - 20);
      }
      if (corner.contains('b')) {
        newBottom = (newBottom + dy).clamp(current.top + 20, widget.image.height.toDouble());
      }

      final updated = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);

      switch (id) {
        case 'red': _red = updated; break;
        case 'blue': _blue = updated; break;
        case 'yellow': _yellow = updated; break;
        case 'green': _green = updated; break;
      }
    });
  }

  Rect _shiftImgRect(Rect rect, Offset delta, Rect displayedImg) {
    final scaleX = widget.image.width / displayedImg.width;
    final scaleY = widget.image.height / displayedImg.height;
    final imgDx = delta.dx * scaleX;
    final imgDy = delta.dy * scaleY;
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();

    final newLeft = (rect.left + imgDx).clamp(0.0, imgW - 30);
    final newTop = (rect.top + imgDy).clamp(0.0, imgH - 20);
    final newRight = newLeft + rect.width;
    final newBottom = newTop + rect.height;

    return Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
  }

  void _save() {
    Navigator.of(context).pop(_FourBoxResult(
      red: _red,
      blue: _blue,
      yellow: _yellow,
      green: _green,
      redExpectedText: _textController.text,
    ));
  }
}

// ── Column Editor Screen ──

class _ColumnEditorScreen extends StatefulWidget {
  final img.Image image;
  final Rect yellowBox;
  final List<_ColumnLine> initialLines;

  const _ColumnEditorScreen({
    required this.image,
    required this.yellowBox,
    required this.initialLines,
  });

  @override
  State<_ColumnEditorScreen> createState() => _ColumnEditorScreenState();
}

class _ColumnEditorScreenState extends State<_ColumnEditorScreen> {
  late List<_ColumnLine> _lines;
  String? _selectedLine;

  @override
  void initState() {
    super.initState();
    _lines = List.from(widget.initialLines);
  }

  // Compute the actual displayed image rect (BoxFit.contain)
  Rect _getDisplayedImageRect(double maxW, double maxH) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    if (imgW == 0 || imgH == 0) return Rect.fromLTWH(0, 0, maxW, maxH);

    final scaleW = maxW / imgW;
    final scaleH = maxH / imgH;
    final scale = scaleW < scaleH ? scaleW : scaleH;

    final displayedW = imgW * scale;
    final displayedH = imgH * scale;
    final offsetX = (maxW - displayedW) / 2;
    final offsetY = (maxH - displayedH) / 2;

    return Rect.fromLTWH(offsetX, offsetY, displayedW, displayedH);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Define Columns'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_lines),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.purple[50],
            child: const Text(
              'Tap + button to add a vertical line (max 5).\n'
              'Drag lines to move. Long press a line to delete.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ),

          // Editor
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final displayedImg = _getDisplayedImageRect(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                final scaleX = displayedImg.width / widget.image.width;
                final scaleY = displayedImg.height / widget.image.height;

                final yellowLeft = displayedImg.left + widget.yellowBox.left * scaleX;
                final yellowTop = displayedImg.top + widget.yellowBox.top * scaleY;
                final yellowW = widget.yellowBox.width * scaleX;
                final yellowH = widget.yellowBox.height * scaleY;

                return Stack(
                  children: [
                    // Background
                    Positioned.fill(
                      child: Container(color: Colors.black),
                    ),
                    // Image
                    Positioned(
                      left: displayedImg.left,
                      top: displayedImg.top,
                      width: displayedImg.width,
                      height: displayedImg.height,
                      child: Image.memory(
                        img.encodeJpg(widget.image, quality: 85),
                        fit: BoxFit.fill,
                      ),
                    ),

                    // YELLOW box highlight
                    Positioned(
                      left: yellowLeft,
                      top: yellowTop,
                      width: yellowW,
                      height: yellowH,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow[700]!, width: 3),
                            color: Colors.yellow.withOpacity(0.25),
                          ),
                        ),
                      ),
                    ),

                    // Vertical lines (using Listener for instant touch response)
                    ...(() {
                      // Sort by x so we can compute gap to each neighbor.
                      final vertical = _lines.where((l) => l.isVertical).toList()
                        ..sort((a, b) => a.x.compareTo(b.x));
                      return vertical.map((line) {
                        final idx = vertical.indexOf(line);
                        // Distance in *displayed pixels* to the nearest other line.
                        double gapPx = double.infinity;
                        if (idx > 0) {
                          gapPx = (line.x - vertical[idx - 1].x).abs() * scaleX;
                        }
                        if (idx < vertical.length - 1) {
                          final rightGap =
                              (vertical[idx + 1].x - line.x).abs() * scaleX;
                          if (rightGap < gapPx) gapPx = rightGap;
                        }
                        // Hit half-width: max 24 (=48px total), shrunk if
                        // neighbors are close so zones never overlap. Minimum
                        // 18 (=36px total) keeps small yellow boxes usable.
                        final hitHalf = gapPx.isFinite
                            ? (gapPx / 2 - 3).clamp(18.0, 24.0)
                            : 24.0;
                        final xInYellow = line.x * scaleX;
                        final xAbsolute = yellowLeft + xInYellow;
                        return Positioned(
                          left: xAbsolute - hitHalf,
                          top: yellowTop,
                          width: hitHalf * 2,
                          height: yellowH,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (_) => _selectLine(line),
                            onPointerMove: (event) {
                              if (event.buttons & 1 != 0) {
                                _moveLine(line, event.delta.dx / scaleX);
                              }
                            },
                            child: Center(
                              child: Container(
                                width: 8,
                                height: yellowH,
                                decoration: BoxDecoration(
                                  color: _selectedLine == line.id
                                      ? Colors.purple
                                      : Colors.purple[400],
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      });
                    })(),

                    // Long press overlay for deleting the selected line
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPress: _deleteSelectedLine,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Action bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Lines: ${_lines.where((l) => l.isVertical).length} / 5',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                FloatingActionButton(
                  onPressed: _lines.where((l) => l.isVertical).length >= 5
                      ? null
                      : _addLine,
                  backgroundColor: Colors.purple,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectLine(_ColumnLine line) {
    setState(() => _selectedLine = line.id);
  }

  void _moveLine(_ColumnLine line, double delta) {
    setState(() {
      line.x = (line.x + delta).clamp(0.0, widget.yellowBox.width);
    });
  }

  void _addLine() {
    if (_lines.where((l) => l.isVertical).length >= 5) return;
    final newLine = _ColumnLine(
      id: 'v${DateTime.now().millisecondsSinceEpoch}',
      x: widget.yellowBox.width * 0.5,
      isVertical: true,
    );
    setState(() {
      _lines.add(newLine);
      _selectedLine = newLine.id;
    });
  }

  void _deleteSelectedLine() {
    if (_selectedLine == null) return;
    if (_lines.where((l) => l.isVertical).length <= 2) return;
    setState(() {
      _lines.removeWhere((l) => l.id == _selectedLine);
      _selectedLine = null;
    });
  }
}

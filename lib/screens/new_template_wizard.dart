import 'dart:io';
import 'package:flutter/material.dart';
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
      case 2: return _verticalLines.length >= 2; // At least 2 vertical lines
      case 3: return _supplierName.isNotEmpty;
      default: return false;
    }
  }

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
    
    // Initialize boxes in top-to-bottom sequence
    _redBox = Rect.fromLTWH(w * 0.05, h * 0.02, w * 0.90, h * 0.08);    // Top
    _blueBox = Rect.fromLTWH(w * 0.05, h * 0.12, w * 0.90, h * 0.06);   // Below red
    _yellowBox = Rect.fromLTWH(w * 0.02, h * 0.20, w * 0.96, h * 0.50); // Middle
    _greenBox = Rect.fromLTWH(w * 0.40, h * 0.75, w * 0.55, h * 0.08); // Bottom
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
      final templateDir = _templateService.templateDirectory;
      final imagePath = '${templateDir.path}/${_template.id}_master.jpg';
      await _masterImage!.copy(imagePath);
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
        final scale = constraints.maxWidth / imgW;
        final scaledH = imgH * scale;

        return Stack(
          children: [
            // Image
            Positioned.fill(
              child: Image.memory(
                img.encodeJpg(_processedImage!, quality: 85),
                fit: BoxFit.contain,
              ),
            ),
            
            // RED Box
            if (_redBox != Rect.zero)
              Positioned(
                left: _redBox.left * scale,
                top: _redBox.top * scale,
                width: _redBox.width * scale,
                height: _redBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 2),
                    color: Colors.red.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('🔴', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            
            // BLUE Box
            if (_blueBox != Rect.zero)
              Positioned(
                left: _blueBox.left * scale,
                top: _blueBox.top * scale,
                width: _blueBox.width * scale,
                height: _blueBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 2),
                    color: Colors.blue.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('🔵', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            
            // YELLOW Box
            if (_yellowBox != Rect.zero)
              Positioned(
                left: _yellowBox.left * scale,
                top: _yellowBox.top * scale,
                width: _yellowBox.width * scale,
                height: _yellowBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellow[700]!, width: 2),
                    color: Colors.yellow.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('🟡', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            
            // GREEN Box
            if (_greenBox != Rect.zero)
              Positioned(
                left: _greenBox.left * scale,
                top: _greenBox.top * scale,
                width: _greenBox.width * scale,
                height: _greenBox.height * scale,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green, width: 2),
                    color: Colors.green.withOpacity(0.1),
                  ),
                  child: const Center(
                    child: Text('🟢', style: TextStyle(fontSize: 20)),
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
              onPressed: _canProceed ? _showSaveDialog : null,
              icon: const Icon(Icons.save),
              label: const Text('Save Template'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
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
              'Tap a box to select it, then drag to move. Use handles to resize.\n'
              'Boxes must NOT overlap and should be top-to-bottom: RED → BLUE → YELLOW → GREEN',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ),
          
          // Editor
          Expanded(
            child: GestureDetector(
              onTapDown: (details) => _onTapDown(details.localPosition),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Image
                      Positioned.fill(
                        child: Image.memory(
                          img.encodeJpg(widget.image, quality: 85),
                          fit: BoxFit.contain,
                        ),
                      ),
                      
                      // RED Box
                      _buildBox('red', _red, Colors.red, () => _selectBox('red')),
                      
                      // BLUE Box
                      _buildBox('blue', _blue, Colors.blue, () => _selectBox('blue')),
                      
                      // YELLOW Box
                      _buildBox('yellow', _yellow, Colors.yellow[700]!, () => _selectBox('yellow')),
                      
                      // GREEN Box
                      _buildBox('green', _green, Colors.green, () => _selectBox('green')),
                    ],
                  );
                },
              ),
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

  Widget _buildBox(String id, Rect rect, Color color, VoidCallback onTap) {
    if (rect == Rect.zero) return const SizedBox();
    
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        onTap: () {
          onTap();
          _selectBox(id);
        },
        onPanUpdate: (details) {
          _moveBox(id, details.delta);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _selectedBox == id ? color : color.withOpacity(0.7),
              width: _selectedBox == id ? 3 : 2,
            ),
            color: color.withOpacity(0.15),
          ),
          child: Stack(
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
              
              // Resize handles (only when selected)
              if (_selectedBox == id) ...[
                // Top-left
                Positioned(left: -4, top: -4, child: _buildHandle(color)),
                // Top-right
                Positioned(right: -4, top: -4, child: _buildHandle(color)),
                // Bottom-left
                Positioned(left: -4, bottom: -4, child: _buildHandle(color)),
                // Bottom-right
                Positioned(right: -4, bottom: -4, child: _buildHandle(color)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  void _onTapDown(Offset position) {
    // Check which box was tapped
    if (_containsPoint(_red, position)) {
      _selectBox('red');
    } else if (_containsPoint(_blue, position)) {
      _selectBox('blue');
    } else if (_containsPoint(_yellow, position)) {
      _selectBox('yellow');
    } else if (_containsPoint(_green, position)) {
      _selectBox('green');
    } else {
      setState(() => _selectedBox = null);
    }
  }

  bool _containsPoint(Rect rect, Offset point) {
    return point.dx >= rect.left && 
           point.dx <= rect.right &&
           point.dy >= rect.top && 
           point.dy <= rect.bottom;
  }

  void _selectBox(String id) {
    setState(() => _selectedBox = id);
  }

  void _moveBox(String id, Offset delta) {
    final imgW = widget.image.width.toDouble();
    final imgH = widget.image.height.toDouble();
    
    setState(() {
      switch (id) {
        case 'red':
          _red = _clampRect(_red.shift(delta), imgW, imgH);
          break;
        case 'blue':
          _blue = _clampRect(_blue.shift(delta), imgW, imgH);
          break;
        case 'yellow':
          _yellow = _clampRect(_yellow.shift(delta), imgW, imgH);
          break;
        case 'green':
          _green = _clampRect(_green.shift(delta), imgW, imgH);
          break;
      }
    });
  }

  Rect _clampRect(Rect rect, double maxW, double maxH) {
    return Rect.fromLTWH(
      rect.left.clamp(0.0, maxW - 20),
      rect.top.clamp(0.0, maxH - 20),
      rect.width.clamp(50.0, maxW),
      rect.height.clamp(20.0, maxH),
    );
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
              'Draw vertical lines to define column boundaries.\n'
              'Tap to select, drag to move. Long press to delete.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ),
          
          // Editor
          Expanded(
            child: GestureDetector(
              onTapDown: (details) => _onTapDown(details.localPosition),
              onLongPress: () => _deleteSelectedLine(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = constraints.maxWidth / widget.image.width;
                  
                  return Stack(
                    children: [
                      // Image
                      Positioned.fill(
                        child: Image.memory(
                          img.encodeJpg(widget.image, quality: 85),
                          fit: BoxFit.contain,
                        ),
                      ),
                      
                      // YELLOW box highlight
                      Positioned(
                        left: widget.yellowBox.left * scale,
                        top: widget.yellowBox.top * scale,
                        width: widget.yellowBox.width * scale,
                        height: widget.yellowBox.height * scale,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow[700]!, width: 3),
                            color: Colors.yellow.withOpacity(0.25),
                          ),
                        ),
                      ),
                      
                      // Vertical lines
                      ..._lines.where((l) => l.isVertical).map((line) {
                        final x = widget.yellowBox.left * scale + line.x * scale;
                        return Positioned(
                          left: x - 1,
                          top: widget.yellowBox.top * scale,
                          child: GestureDetector(
                            onTap: () => _selectLine(line),
                            onPanUpdate: (details) => _moveLine(line, details.delta.dx / scale),
                            child: Container(
                              width: 3,
                              height: widget.yellowBox.height * scale,
                              color: _selectedLine == line.id ? Colors.purple : Colors.purple[300],
                            ),
                          ),
                        );
                      }),
                      
                      // Add line button
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton(
                          onPressed: _addLine,
                          backgroundColor: Colors.purple,
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTapDown(Offset position) {
    // Check if tapped on a line
    for (final line in _lines.where((l) => l.isVertical)) {
      final lineX = widget.yellowBox.left + line.x;
      if ((position.dx - lineX).abs() < 15) {
        _selectLine(line);
        return;
      }
    }
    setState(() => _selectedLine = null);
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
    // Don't allow deleting if less than 2 lines
    if (_lines.where((l) => l.isVertical).length <= 2) return;
    
    setState(() {
      _lines.removeWhere((l) => l.id == _selectedLine);
      _selectedLine = null;
    });
  }
}

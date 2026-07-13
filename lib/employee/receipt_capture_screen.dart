import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Real camera/gallery receipt capture screen using image_picker.
class ReceiptCaptureScreen extends StatefulWidget {
  final bool useGallery;
  const ReceiptCaptureScreen({super.key, this.useGallery = false});

  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  static const Color obsidianBlack = Color(0xFF0D0D11);
  static const Color darkCharcoal = Color(0xFF16161F);
  static const Color champagneGold = Color(0xFFE2B93B);
  static const Color textFrost = Color(0xFFF3F4F6);
  static const Color textMuted = Color(0xFF9CA3AF);

  final ImagePicker _picker = ImagePicker();
  Uint8List? _previewBytes;
  String? _fileName;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Open the camera/gallery automatically as soon as this screen appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  Future<void> _pickImage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final XFile? picked = await _picker.pickImage(
        source: widget.useGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null) {
        // User cancelled the picker — just stop loading, keep screen open.
        setState(() => _isLoading = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      setState(() {
        _previewBytes = bytes;
        _fileName = picked.name;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = widget.useGallery
            ? 'Could not access gallery. Please check app permissions.'
            : 'Could not access camera. Please check app permissions.';
      });
    }
  }

  void _confirmAndReturn() {
    if (_fileName != null) {
      Navigator.pop(context, _fileName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: obsidianBlack,
      appBar: AppBar(
        backgroundColor: darkCharcoal,
        elevation: 0,
        title: Text(
          widget.useGallery ? 'Choose from Gallery' : 'Scan Receipt',
          style: const TextStyle(color: textFrost, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: darkCharcoal,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: champagneGold.withValues(alpha: 0.4), width: 2),
                ),
                child: _buildContent(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _pickImage,
                    icon: Icon(
                      widget.useGallery ? Icons.photo_library_rounded : Icons.camera_alt_rounded,
                      size: 18,
                      color: champagneGold,
                    ),
                    label: Text(
                      _previewBytes == null ? 'Open ${widget.useGallery ? 'Gallery' : 'Camera'}' : 'Retake',
                      style: const TextStyle(color: champagneGold, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: champagneGold.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _previewBytes == null ? null : _confirmAndReturn,
                    icon: const Icon(Icons.check_rounded, color: obsidianBlack),
                    label: const Text('Use This Receipt', style: TextStyle(fontWeight: FontWeight.bold, color: obsidianBlack)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: champagneGold,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: champagneGold)),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: textFrost, fontSize: 14), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    if (_previewBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(_previewBytes!, fit: BoxFit.contain, height: 400),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_rounded, size: 64, color: champagneGold),
          const SizedBox(height: 16),
          Text(
            widget.useGallery ? 'Select a receipt image' : 'Point your camera at the receipt',
            style: const TextStyle(color: textFrost, fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
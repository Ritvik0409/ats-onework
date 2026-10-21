import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ui/tokens.dart';
import '../ui/widgets.dart';

/// Real camera/gallery receipt capture screen using image_picker.
class ReceiptCaptureScreen extends StatefulWidget {
  const ReceiptCaptureScreen({super.key, this.useGallery = false});

  final bool useGallery;

  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _previewBytes;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Open the camera/gallery automatically as soon as this screen appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickImage());
  }

  Future<void> _pickImage() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final XFile? picked = await _picker.pickImage(
        source: widget.useGallery ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 85,
      );
      // The user can leave the screen while the picker or the camera is
      // open, so every state change below checks that it is still alive.
      if (!mounted) return;
      if (picked == null) {
        // User cancelled the picker — just stop loading, keep screen open.
        setState(() => _isLoading = false);
        return;
      }
      final Uint8List bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = widget.useGallery
            ? 'Could not access the gallery. Please check app permissions.'
            : 'Could not access the camera. Please check app permissions.';
      });
    }
  }

  void _confirmAndReturn() {
    // Return the actual image bytes — the expense form's collector
    // expects Uint8List (upload happens at final submit). Returning a
    // String filename here used to break "Scan with Camera" entirely.
    if (_previewBytes != null) {
      Navigator.pop(context, _previewBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        title: Text(widget.useGallery ? 'Choose from gallery' : 'Scan receipt'),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: _buildContent(palette),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _pickImage,
                    icon: Icon(
                      widget.useGallery
                          ? Icons.photo_library_rounded
                          : Icons.camera_alt_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _previewBytes == null
                          ? 'Open ${widget.useGallery ? 'gallery' : 'camera'}'
                          : 'Retake',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _previewBytes == null ? null : _confirmAndReturn,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Use this receipt',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

  Widget _buildContent(AppPalette palette) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Capture failed',
          message: _errorMessage!,
        ),
      );
    }

    if (_previewBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Image.memory(_previewBytes!, fit: BoxFit.contain, height: 400),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.receipt_long_rounded, size: 56, color: palette.gold),
          const SizedBox(height: 14),
          Text(
            widget.useGallery
                ? 'Select a receipt image'
                : 'Point your camera at the receipt',
            style: TextStyle(
              color: palette.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

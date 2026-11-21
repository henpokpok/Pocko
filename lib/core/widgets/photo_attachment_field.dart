import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/media/receipt_photo_service.dart';
import '../theme/app_theme.dart';

/// Opens [base64Jpeg] full screen with pinch-to-zoom.
void showFullscreenPhoto(BuildContext context, String base64Jpeg) {
  Uint8List bytes;
  try {
    bytes = base64Decode(base64Jpeg);
  } catch (_) {
    return;
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              key: const ValueKey('receipt_fullscreen'),
              maxScale: 6,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton.filled(
                key: const ValueKey('receipt_fullscreen_close'),
                tooltip: 'Close',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white24,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A receipt / transfer-slip photo slot: Take Photo (camera) or Choose from
/// Gallery, then a preview that opens full screen, with Retake / Remove.
///
/// The value is a compact base64 JPEG (see [ReceiptPhotoService]).
class PhotoAttachmentField extends StatefulWidget {
  final String title;
  final String? base64;
  final ValueChanged<String?> onChanged;

  const PhotoAttachmentField({
    super.key,
    required this.title,
    required this.base64,
    required this.onChanged,
  });

  @override
  State<PhotoAttachmentField> createState() => _PhotoAttachmentFieldState();
}

class _PhotoAttachmentFieldState extends State<PhotoAttachmentField> {
  String? _cachedFor;
  Uint8List? _bytes;
  String? _error;
  bool _busy = false;

  Uint8List? get _decoded {
    final b64 = widget.base64;
    if (b64 != _cachedFor) {
      _cachedFor = b64;
      try {
        _bytes = (b64 == null || b64.isEmpty) ? null : base64Decode(b64);
      } catch (_) {
        _bytes = null;
      }
    }
    return _bytes;
  }

  Future<void> _pick(ReceiptSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ReceiptPhotoService.pick(source);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });
    if (result.base64 != null) widget.onChanged(result.base64);
  }

  Widget _action({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        key: key,
        onPressed: _busy ? null : onTap,
        icon: Icon(icon, size: 18),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryEmeraldDark,
          side: const BorderSide(color: AppTheme.borderColor, width: 2),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decoded;
    return Container(
      key: const ValueKey('receipt_section'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppTheme.primaryEmeraldDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (bytes != null) ...[
            GestureDetector(
              key: const ValueKey('receipt_preview'),
              onTap: () => showFullscreenPhoto(context, widget.base64!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                // Fixed height: the layout never jumps while the image decodes.
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    // The preview is at most a phone wide: decode it that small.
                    cacheWidth: 900,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Text('Photo cannot be shown')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the photo to view it full screen',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _action(
                  key: const ValueKey('receipt_replace'),
                  icon: Icons.photo_camera_rounded,
                  label: 'Retake',
                  onTap: () => _pick(ReceiptSource.camera),
                ),
                const SizedBox(width: 8),
                _action(
                  key: const ValueKey('receipt_remove'),
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  onTap: () {
                    setState(() => _error = null);
                    widget.onChanged(null);
                  },
                ),
              ],
            ),
          ] else
            Row(
              children: [
                _action(
                  key: const ValueKey('receipt_camera'),
                  icon: Icons.photo_camera_rounded,
                  label: 'Take Photo',
                  onTap: () => _pick(ReceiptSource.camera),
                ),
                const SizedBox(width: 8),
                _action(
                  key: const ValueKey('receipt_gallery'),
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from Gallery',
                  onTap: () => _pick(ReceiptSource.gallery),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                key: const ValueKey('receipt_error'),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.coralOwesText,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

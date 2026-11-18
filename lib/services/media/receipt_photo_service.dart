import 'dart:convert';

import 'package:image_picker/image_picker.dart';

/// Where a receipt / slip photo comes from.
enum ReceiptSource { camera, gallery }

/// Picks a receipt or bank-slip photo and returns it as a compact base64 JPEG,
/// so it works offline and travels inside the synced trip document.
///
/// The picture is downscaled (longest side 900 px) and re-encoded at JPEG
/// quality 55 by the platform picker (about 60-150 KB), and anything still above
/// [maxBase64Chars] is rejected rather than risking the document size limit.
class ReceiptPhotoService {
  ReceiptPhotoService._();

  static const int maxBase64Chars = 450 * 1024;
  static const double maxSide = 900;
  static const int jpegQuality = 55;

  /// Replace in tests to avoid the real camera / gallery.
  static Future<ReceiptPhotoResult> Function(ReceiptSource source) pick =
      _pickWithImagePicker;

  static final ImagePicker _picker = ImagePicker();

  static Future<ReceiptPhotoResult> _pickWithImagePicker(
    ReceiptSource source,
  ) async {
    try {
      final file = await _picker.pickImage(
        source: source == ReceiptSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: maxSide,
        maxHeight: maxSide,
        imageQuality: jpegQuality,
      );
      if (file == null) return const ReceiptPhotoResult.cancelled();
      final b64 = base64Encode(await file.readAsBytes());
      if (b64.length > maxBase64Chars) {
        return const ReceiptPhotoResult.error(
          'That photo is too large to sync. Try a smaller picture.',
        );
      }
      return ReceiptPhotoResult.ok(b64);
    } catch (e) {
      // Permission denied, no camera on this device, picker unavailable...
      return ReceiptPhotoResult.error(
        source == ReceiptSource.camera
            ? 'Could not open the camera. Check the camera permission.'
            : 'Could not open the photo library. Check the photo permission.',
      );
    }
  }
}

class ReceiptPhotoResult {
  /// Base64 JPEG, or `null` when cancelled / failed.
  final String? base64;
  final String? error;
  final bool cancelled;

  const ReceiptPhotoResult.ok(String this.base64)
    : error = null,
      cancelled = false;
  const ReceiptPhotoResult.cancelled()
    : base64 = null,
      error = null,
      cancelled = true;
  const ReceiptPhotoResult.error(String this.error)
    : base64 = null,
      cancelled = false;
}

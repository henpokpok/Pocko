import 'package:flutter/material.dart';

import '../../models/bank_slip.dart';
import '../theme/app_theme.dart';

/// Thumbnail of a candidate slip: the real photo for uploads, otherwise a small
/// painted receipt (header, line items and a bold total) so every slip has a
/// recognisable preview.
class SlipThumbnail extends StatelessWidget {
  final BankSlip slip;
  final double width;
  final double height;

  const SlipThumbnail({
    super.key,
    required this.slip,
    this.width = 46,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = slip.previewBytes;
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _paper(),
            )
          : _paper(),
    );
  }

  Widget _paper() => CustomPaint(
    painter: _ReceiptPainter(
      lines: slip.isItemized ? slip.lineItems.length.clamp(2, 6) : 2,
      accent: slip.isItemized
          ? const Color(0xFF1D4ED8)
          : AppTheme.primaryEmeraldDark,
    ),
  );
}

class _ReceiptPainter extends CustomPainter {
  final int lines;
  final Color accent;

  _ReceiptPainter({required this.lines, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final grey = Paint()..color = const Color(0xFFE2E8F0);
    final dark = Paint()..color = const Color(0xFF475569);
    final pad = size.width * 0.14;

    // Header (shop name)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, size.height * 0.1, size.width * 0.5, 3.5),
        const Radius.circular(2),
      ),
      Paint()..color = accent.withValues(alpha: 0.85),
    );

    // Line items
    var y = size.height * 0.26;
    final step = (size.height * 0.46) / lines;
    for (var i = 0; i < lines; i++) {
      final w = size.width * (0.45 + 0.3 * ((i * 37) % 10) / 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(pad, y, w, 2.6),
          const Radius.circular(2),
        ),
        grey,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width - pad - size.width * 0.16,
            y,
            size.width * 0.16,
            2.6,
          ),
          const Radius.circular(2),
        ),
        grey,
      );
      y += step;
    }

    // Total
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width - pad - size.width * 0.34,
          size.height * 0.82,
          size.width * 0.34,
          4,
        ),
        const Radius.circular(2),
      ),
      dark,
    );

    // Torn bottom edge
    final tear = Path()..moveTo(0, size.height);
    const teeth = 6;
    for (var i = 0; i <= teeth; i++) {
      final x = size.width * i / teeth;
      tear.lineTo(x, size.height - (i.isEven ? 0 : 3.5));
    }
    tear.lineTo(size.width, size.height);
    tear.close();
    canvas.drawPath(tear, Paint()..color = const Color(0xFFF8FAFC));
  }

  @override
  bool shouldRepaint(covariant _ReceiptPainter old) =>
      old.lines != lines || old.accent != accent;
}

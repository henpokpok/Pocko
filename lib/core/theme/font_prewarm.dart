import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FontWeight;
import 'package:google_fonts/google_fonts.dart';

/// Loads every Plus Jakarta Sans weight the UI uses before the first frame, so
/// a late font swap never relays out the whole tree in the middle of a swipe.
///
/// It is bounded: on a slow network the app still starts after [timeout] and
/// falls back to the platform font until the files arrive.
class FontPrewarm {
  const FontPrewarm._();

  /// Weights used across the app (see `fontWeight:` usages).
  static const List<FontWeight> weights = [
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
    FontWeight.w900,
  ];

  /// Requests all weights and waits for them, never longer than [timeout].
  /// Returns `true` when everything loaded in time. Never throws.
  static Future<bool> prewarm({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    try {
      // Creating a style starts the (cached) font load.
      for (final w in weights) {
        GoogleFonts.plusJakartaSans(fontWeight: w);
      }
      await GoogleFonts.pendingFonts().timeout(timeout);
      return true;
    } on TimeoutException {
      debugPrint(
        '[FontPrewarm] Fonts still loading after $timeout; continuing.',
      );
      return false;
    } catch (e) {
      debugPrint('[FontPrewarm] Font preload skipped: $e');
      return false;
    }
  }
}

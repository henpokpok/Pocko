import 'dart:async';

import 'package:google_fonts/google_fonts.dart';

/// Global test setup: never try to download fonts from the network.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  await testMain();
}

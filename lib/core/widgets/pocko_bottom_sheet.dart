import 'package:flutter/material.dart';

/// Fraction of the screen height a Pocko bottom sheet may occupy.
const double kPockoSheetMaxHeightFactor = 0.80;

/// The one way to open a bottom sheet in Pocko.
///
/// * Height is capped at 80% of the screen so a sheet never crams against the
///   top edge; content scrolls inside (set [scrollable] to `false` when the
///   [builder] already returns its own scrollable, e.g. a `ListView`).
/// * Draggable with a drag handle, 28 px rounded top corners, swipe down to
///   dismiss, and the keyboard inset is added as bottom padding so text fields
///   are never covered.
Future<T?> showPockoBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool scrollable = true,
  bool useRootNavigator = false,
}) {
  final maxHeight =
      MediaQuery.sizeOf(context).height * kPockoSheetMaxHeightFactor;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final inset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      final content = Builder(builder: builder);
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: scrollable
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: content,
              )
            : content,
      );
    },
  );
}

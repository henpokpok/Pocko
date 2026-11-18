import 'package:flutter/material.dart';

/// Shared responsive breakpoints.
class Breakpoints {
  Breakpoints._();

  /// Tablet (iPad Air M4 portrait) and desktop web start here.
  static const double wide = 768;

  /// Roomy desktop layouts start here.
  static const double desktop = 1100;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// Single-column on phones, balanced two-column dashboard on tablet / desktop.
///
/// Both columns live inside the screen's own scroll view, so the layout never
/// introduces nested scrolling or unbounded-height errors.
class AdaptiveColumns extends StatelessWidget {
  final List<Widget> left;
  final List<Widget> right;
  final double gap;

  /// Flex ratio of the left column to the right column on wide screens.
  final int leftFlex;
  final int rightFlex;

  const AdaptiveColumns({
    super.key,
    required this.left,
    required this.right,
    this.gap = 20,
    this.leftFlex = 1,
    this.rightFlex = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= Breakpoints.wide - 40;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...left, ...right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: leftFlex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left,
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: rightFlex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Scroll body used by every tab: consistent padding, bottom room for the
/// floating nav on phones, and a max content width on huge screens.
class TabScrollBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;

  const TabScrollBody({
    super.key,
    required this.children,
    this.maxWidth = 1080,
  });

  @override
  Widget build(BuildContext context) {
    final wide = Breakpoints.isWide(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            wide ? 28 : 20,
            12,
            wide ? 28 : 20,
            wide ? 40 : 116,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

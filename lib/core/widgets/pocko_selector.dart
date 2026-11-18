import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// One row of a [PockoSelector] popover.
class PockoMenuEntry<T> {
  final T value;
  final String label;

  /// Optional icon shown in a pastel circle; without it a color dot is used.
  final IconData? icon;

  /// Optional emoji (e.g. a country flag) shown in the circle instead of an icon.
  final String? emoji;
  final Color accent;
  final Color pastel;

  const PockoMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.emoji,
    this.accent = AppTheme.primaryEmerald,
    this.pastel = AppTheme.primaryEmeraldLight,
  });
}

/// Pocko-styled replacement for raw `DropdownButton` / unstyled popups: a
/// rounded pill trigger that opens a soft 24 px popover with pastel accents,
/// icons or color dots and Plus Jakarta Sans type.
class PockoSelector<T> extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final Color? leadingColor;
  final T? selected;
  final List<PockoMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final VoidCallback? onOpened;
  final String tooltip;

  /// Light text/pill on a dark overlay (`true`) or dark text on a light card.
  final bool onDark;
  final bool compact;

  const PockoSelector({
    super.key,
    required this.label,
    required this.entries,
    required this.onSelected,
    this.selected,
    this.leadingIcon,
    this.leadingColor,
    this.onOpened,
    this.tooltip = '',
    this.onDark = true,
    this.compact = false,
  });

  /// Corner radius of the popover.
  static const double menuRadius = 24;

  /// The popover never grows taller than this; longer lists scroll.
  static const double menuMaxHeight = 320;

  /// Lists with more entries than this get an instant search field.
  static const int searchThreshold = 5;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : AppTheme.textDark;
    return PopupMenuButton<T>(
      tooltip: tooltip,
      onOpened: onOpened,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: Colors.white,
      elevation: 12,
      shadowColor: const Color(0x55000000),
      surfaceTintColor: Colors.transparent,
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(menuRadius),
      ),
      itemBuilder: (_) => [
        _SelectorPanel<T>(entries: entries, selected: selected),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 5 : 8,
        ),
        decoration: ShapeDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : const Color(0xFFF1F5F9),
          shape: StadiumBorder(
            side: BorderSide(
              color: onDark
                  ? Colors.white.withValues(alpha: 0.32)
                  : AppTheme.borderColor,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingIcon != null) ...[
              Icon(
                leadingIcon,
                size: compact ? 14 : 16,
                color: leadingColor ?? fg,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: compact ? 12 : 13.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}

/// The popover body: an optional search field above a scrollable list, capped
/// at [PockoSelector.menuMaxHeight].
class _SelectorPanel<T> extends PopupMenuEntry<T> {
  final List<PockoMenuEntry<T>> entries;
  final T? selected;

  const _SelectorPanel({required this.entries, required this.selected});

  @override
  double get height => PockoSelector.menuMaxHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<_SelectorPanel<T>> createState() => _SelectorPanelState<T>();
}

class _SelectorPanelState<T> extends State<_SelectorPanel<T>> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _searchable => widget.entries.length > PockoSelector.searchThreshold;

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? widget.entries
        : widget.entries
              .where((e) => e.label.toLowerCase().contains(q))
              .toList();

    return ConstrainedBox(
      key: const ValueKey('selector_panel'),
      constraints: const BoxConstraints(maxHeight: PockoSelector.menuMaxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: TextField(
                key: const ValueKey('selector_search'),
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(99),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Flexible(
            child: shown.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'No matches',
                      key: const ValueKey('selector_empty'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSlate,
                      ),
                    ),
                  )
                // A Column in a scroll view (not a shrink-wrapped ListView):
                // the popup measures intrinsic width, which lazy viewports
                // cannot answer. Option lists are short, so nothing is lost.
                : SingleChildScrollView(
                    key: const ValueKey('selector_list'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [for (final e in shown) _row(context, e)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PockoMenuEntry<T> e) {
    final isSelected = e.value == widget.selected;
    return InkWell(
      key: ValueKey('selector_row_${e.label}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.pop<T>(context, e.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? e.pastel.withValues(alpha: 0.55)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: e.pastel,
                  shape: BoxShape.circle,
                ),
                child: e.emoji != null
                    ? Center(
                        child: Text(
                          e.emoji!,
                          style: const TextStyle(fontSize: 16),
                        ),
                      )
                    : e.icon != null
                    ? Icon(e.icon, size: 16, color: e.accent)
                    : Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: e.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 18, color: e.accent),
            ],
          ),
        ),
      ),
    );
  }
}

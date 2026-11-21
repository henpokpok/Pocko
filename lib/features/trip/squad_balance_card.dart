import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/tactile.dart';
import 'trip_state.dart';

/// Live group net-balance strip used on Home and Expenses.
///
/// Rings are emerald when a traveler is owed money, coral when they owe, and
/// grey when square. Everything is derived from [TripState.netBalances], which
/// already includes recorded settlements.
class SquadBalanceCard extends StatelessWidget {
  final TripState tripState;
  final VoidCallback? onManage;

  /// Show a trailing "+ Group" invite orb (Home).
  final bool showInviteOrb;
  final String trailingLabel;

  const SquadBalanceCard({
    super.key,
    required this.tripState,
    this.onManage,
    this.showInviteOrb = false,
    this.trailingLabel = 'Manage Group →',
  });

  @override
  Widget build(BuildContext context) {
    final trip = tripState.trip;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.surfaceDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'GROUP NET BALANCE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              if (onManage != null)
                Tactile(
                  onTap: onManage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      trailingLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryEmerald,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final member in trip.members)
                  _MemberOrb(
                    name: tripState.displayName(member),
                    initial: member.name.isNotEmpty
                        ? member.name[0].toUpperCase()
                        : '?',
                    net: tripState.netBalances[member.id] ?? 0.0,
                    currency: trip.baseCurrency,
                  ),
                // The header already has "Manage Group →"; the extra invite orb
                // only shows for small groups, so a 4+ person row never clips.
                if (showInviteOrb && trip.members.length < 4)
                  Tactile(
                    onTap: onManage,
                    semanticLabel: 'Invite a friend',
                    child: Column(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFF8FAFC),
                            border: Border.all(
                              color: AppTheme.borderColor,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            color: AppTheme.primaryEmerald,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '+ Group',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textSlate,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Invite',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberOrb extends StatelessWidget {
  final String name;
  final String initial;
  final double net;
  final String currency;

  const _MemberOrb({
    required this.name,
    required this.initial,
    required this.net,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final isGets = net > 0.5;
    final isOwes = net < -0.5;
    final ringColor = isGets
        ? AppTheme.primaryEmerald
        : (isOwes ? AppTheme.coralOwes : AppTheme.textMuted);
    final badgeBg = isGets
        ? AppTheme.primaryEmeraldLight
        : (isOwes ? AppTheme.coralOwesBg : const Color(0xFFF1F5F9));
    final badgeText = isGets
        ? AppTheme.primaryEmeraldDark
        : (isOwes ? AppTheme.coralOwesText : AppTheme.textSlate);

    return Container(
      margin: const EdgeInsets.only(right: 14),
      constraints: const BoxConstraints(minWidth: 64),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: ringColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: ringColor.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ringColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isGets
                  ? '+${CurrencyHelper.formatAmount(net, currency)}'
                  : (isOwes
                        ? CurrencyHelper.formatAmount(net, currency)
                        : 'Settled'),
              style: AppTheme.tabularNumberStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: badgeText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/widgets/pocko_selector.dart';
import 'trip_destinations.dart';

/// Interactive first-trip setup: trip name, destination (which pairs the trip
/// currency), home currency and group members as simple name tags.
class FirstTripSetupCard extends StatefulWidget {
  final ValueChanged<TripSetupData> onStart;
  const FirstTripSetupCard({super.key, required this.onStart});

  @override
  State<FirstTripSetupCard> createState() => _FirstTripSetupCardState();
}

class _FirstTripSetupCardState extends State<FirstTripSetupCard> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _friend = TextEditingController();
  final FocusNode _friendFocus = FocusNode();
  final List<String> _friends = [];

  TripDestination _destination = TripDestination.all.first;
  late String _tripCurrency = _destination.currency;
  String _homeCurrency = 'USD';
  String? _error;
  String? _friendError;

  @override
  void dispose() {
    _name.dispose();
    _friend.dispose();
    _friendFocus.dispose();
    super.dispose();
  }

  void _addFriend() {
    final n = _friend.text.trim();
    if (n.isEmpty) return;
    if (n.toLowerCase() == 'you' ||
        _friends.any((f) => f.toLowerCase() == n.toLowerCase())) {
      setState(() => _friendError = '“$n” is already in the group');
      return;
    }
    setState(() {
      _friends.add(n);
      _friend.clear();
      _friendError = null;
    });
  }

  void _start() {
    // A name typed but not yet added still counts as a friend.
    if (_friend.text.trim().isNotEmpty) _addFriend();
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give your trip a name first');
      return;
    }
    widget.onStart(
      TripSetupData(
        name: _name.text.trim(),
        destination: _destination,
        tripCurrency: _tripCurrency,
        homeCurrency: _homeCurrency,
        friends: List<String>.unmodifiable(_friends),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: AppTheme.textSlate,
      ),
    ),
  );

  List<PockoMenuEntry<String>> _currencyEntries() => [
    for (final code in CurrencyHelper.currencySymbols.keys)
      PockoMenuEntry<String>(
        value: code,
        label:
            '$code ${CurrencyHelper.currencySymbols[code]} • ${CurrencyHelper.currencyNames[code] ?? ''}',
        pastel: const Color(0xFFDCF0FF),
        accent: const Color(0xFF3B82F6),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('first_trip_setup_card'),
      padding: const EdgeInsets.all(22),
      decoration: AppTheme.surfaceDecoration(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Set up your first trip',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Takes about 20 seconds. You can change everything later.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSlate,
            ),
          ),
          const SizedBox(height: 16),
          _label('TRIP NAME'),
          TextField(
            key: const ValueKey('trip_name_field'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: 'Seoul Autumn Trip',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 14),
          _label('DESTINATION'),
          Align(
            alignment: Alignment.centerLeft,
            child: PockoSelector<String>(
              key: const ValueKey('destination_selector'),
              onDark: false,
              tooltip: 'Destination country',
              leadingIcon: Icons.public_rounded,
              leadingColor: AppTheme.primaryEmeraldDark,
              label: _destination.flagAndName,
              selected: _destination.name,
              onSelected: (n) => setState(() {
                _destination = TripDestination.byName(n);
                _tripCurrency = _destination.currency;
              }),
              entries: [
                for (final d in TripDestination.all)
                  PockoMenuEntry<String>(
                    value: d.name,
                    label: d.rowLabel(CurrencyHelper.symbol(d.currency)),
                    emoji: d.flag,
                    accent: AppTheme.primaryEmeraldDark,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _label('CURRENCIES'),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              PockoSelector<String>(
                key: const ValueKey('trip_currency_selector'),
                onDark: false,
                tooltip: 'Trip currency',
                leadingIcon: Icons.flight_takeoff_rounded,
                leadingColor: AppTheme.primaryEmeraldDark,
                label:
                    'Trip: ${CurrencyHelper.symbol(_tripCurrency)} $_tripCurrency',
                selected: _tripCurrency,
                onSelected: (c) => setState(() => _tripCurrency = c),
                entries: _currencyEntries(),
              ),
              PockoSelector<String>(
                key: const ValueKey('home_currency_selector'),
                onDark: false,
                tooltip: 'Home currency',
                leadingIcon: Icons.home_rounded,
                leadingColor: AppTheme.primaryEmeraldDark,
                label:
                    'Home: ${CurrencyHelper.symbol(_homeCurrency)} $_homeCurrency',
                selected: _homeCurrency,
                onSelected: (c) => setState(() => _homeCurrency = c),
                entries: _currencyEntries(),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label('GROUP MEMBERS'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('member_name_field'),
                  controller: _friend,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  focusNode: _friendFocus,
                  onSubmitted: (_) {
                    _addFriend();
                    // Keep typing: the next friend goes in right away.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _friendFocus.requestFocus();
                    });
                  },
                  onChanged: (_) {
                    if (_friendError != null) {
                      setState(() => _friendError = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Add a friend’s name',
                    errorText: _friendError,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const ValueKey('add_member_button'),
                tooltip: 'Add friend',
                onPressed: _addFriend,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(
                key: const ValueKey('member_tag_you'),
                avatar: const Icon(
                  Icons.person_rounded,
                  size: 16,
                  color: AppTheme.primaryEmeraldDark,
                ),
                label: const Text('You'),
                backgroundColor: AppTheme.primaryEmeraldLight,
                shape: const StadiumBorder(),
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppTheme.primaryEmeraldDark,
                ),
              ),
              for (final f in _friends)
                InputChip(
                  key: ValueKey('member_tag_$f'),
                  label: Text(f),
                  onDeleted: () => setState(() => _friends.remove(f)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  backgroundColor: const Color(0xFFF1F5F9),
                  shape: const StadiumBorder(),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.phonelink_off_rounded,
                size: 15,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'No app install needed for friends',
                  key: const ValueKey('no_install_hint'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            key: const ValueKey('start_trip_button'),
            onPressed: _start,
            icon: const Icon(Icons.flight_takeoff_rounded, size: 22),
            label: const Text('Start Trip'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryEmerald,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 58),
              shape: RoundedRectangleBorder(borderRadius: AppTheme.pillRadius),
              textStyle: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

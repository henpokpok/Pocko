import 'package:flutter/material.dart';

/// Status of the expense item in relation to a banking transaction slip
enum SlipStatus {
  waitingForSlip(
    'waitingForSlip',
    'Waiting for slip',
    Icons.receipt_long_outlined,
    Color(0xFFB45309),
    Color(0xFFFFF4E0),
  ),
  matched(
    'matched',
    'Matched & Verified',
    Icons.verified_rounded,
    Color(0xFF047857),
    Color(0xFFE8F8F0),
  ),

  /// Paid in cash: no receipt image is needed and the expense stays clean.
  cash(
    'cash',
    'Paid in cash',
    Icons.payments_rounded,
    Color(0xFF475569),
    Color(0xFFEEF2F6),
  );

  final String rawValue;
  final String label;
  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;

  const SlipStatus(
    this.rawValue,
    this.label,
    this.icon,
    this.foregroundColor,
    this.backgroundColor,
  );

  static SlipStatus fromRaw(String? raw) {
    if (raw == null) return SlipStatus.waitingForSlip;
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'matched' || normalized == 'verified') {
      return SlipStatus.matched;
    }
    if (normalized == 'cash') return SlipStatus.cash;
    return SlipStatus.waitingForSlip;
  }
}

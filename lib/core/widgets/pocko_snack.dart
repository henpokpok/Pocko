import 'package:flutter/material.dart';

import 'pocko_toast.dart';

/// Compatibility wrapper: every message in the app is shown as a
/// [showPockoToast] pill card (auto-dismissing after 5 s, replacing any toast
/// already on screen).
void showPockoSnack(
  BuildContext context,
  String message, {
  String? detail,
  IconData? icon,
  String? actionLabel,
  VoidCallback? onAction,
  bool success = true,
}) {
  showPockoToast(
    context,
    message: message,
    detail: detail,
    icon: icon,
    kind: success ? PockoToastKind.success : PockoToastKind.error,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

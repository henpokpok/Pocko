/// `"(3) Liam, Maya, Alex"` – the explicit summary of who is in a split.
///
/// [names] keep their order. When the list does not fit in [maxChars] it is cut
/// on a name boundary and ends with an ellipsis, e.g. `"(6) Liam, Maya, Alex…"`.
String formatSelectedNames(List<String> names, {int maxChars = 34}) {
  final clean = [
    for (final n in names)
      if (n.trim().isNotEmpty) n.trim(),
  ];
  if (clean.isEmpty) return '';
  final prefix = '(${clean.length}) ';
  final buf = StringBuffer(prefix);
  var shown = 0;
  for (final name in clean) {
    final next = shown == 0 ? name : ', $name';
    if (shown > 0 && buf.length + next.length > maxChars) break;
    buf.write(next);
    shown++;
  }
  var out = buf.toString();
  if (shown < clean.length) out = '$out…';
  // A single very long name is trimmed too.
  if (out.length > maxChars + 3 && shown == 1) {
    out = '${out.substring(0, maxChars)}…';
  }
  return out;
}

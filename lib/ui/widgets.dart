import 'package:flutter/material.dart';

import '../core/report.dart';
import '../core/sessions.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

Color outcomeColor(BuildContext context, Outcome o) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (o) {
    Outcome.ok => dark ? const Color(0xFF6FD39A) : const Color(0xFF1E8E4E),
    Outcome.slow => dark ? const Color(0xFFE9C46A) : const Color(0xFFB07D00),
    Outcome.retry => dark ? const Color(0xFFF4A261) : const Color(0xFFC25E00),
    Outcome.drop => dark ? const Color(0xFFFF8A80) : const Color(0xFFC62828),
    Outcome.fail => dark ? const Color(0xFFFF8A80) : const Color(0xFFB71C1C),
    Outcome.wired => Theme.of(context).colorScheme.outline,
    Outcome.ongoing => Theme.of(context).colorScheme.primary,
  };
}

IconData outcomeIcon(Outcome o) => switch (o) {
      Outcome.ok => Icons.check_circle,
      Outcome.slow => Icons.hourglass_bottom,
      Outcome.retry => Icons.autorenew,
      Outcome.drop => Icons.link_off,
      Outcome.fail => Icons.error,
      Outcome.wired => Icons.usb,
      Outcome.ongoing => Icons.sync,
    };

class OutcomeChip extends StatelessWidget {
  const OutcomeChip(this.o, {super.key});
  final Outcome o;

  @override
  Widget build(BuildContext context) {
    final c = outcomeColor(context, o);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(outcomeIcon(o), size: 15, color: c),
        const SizedBox(width: 5),
        Text(outcomeLabel(o), style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12.5)),
      ]),
    );
  }
}

/// Subtle two-column table.
class KvTable extends StatelessWidget {
  const KvTable(this.rows, {super.key});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 4, child: Text(k, style: TextStyle(color: muted, fontSize: 13.5))),
              Expanded(flex: 6, child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
      ],
    );
  }
}

class StatBox extends StatelessWidget {
  const StatBox(this.value, this.label, {super.key, this.color});
  final String value, label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
}

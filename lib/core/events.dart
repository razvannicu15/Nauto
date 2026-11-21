import 'dart:convert';

/// One line of the monitor's journal (events.jsonl).
class Ev {
  Ev(this.ts, this.t, this.d);

  final int ts;
  final String t;
  final Map<String, dynamic> d;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(ts);
  bool get on => d['on'] == true;
  bool get dongle => d['dongle'] == true;
  String? get ssid => d['ssid'] as String?;
  String? get dev => d['dev'] as String?;
  int? intOf(String k) => (d[k] as num?)?.toInt();

  /// Android Auto projection (androidx.car.app CarConnection type 2).
  bool get isProjection => t == 'aa' && intOf('type') == 2;

  static List<Ev> parse(String text) {
    final out = <Ev>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      try {
        final m = jsonDecode(line) as Map<String, dynamic>;
        final ts = (m.remove('ts') as num).toInt();
        final t = m.remove('t') as String;
        out.add(Ev(ts, t, m));
      } catch (_) {
        // half-written line: skip
      }
    }
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return out;
  }

  /// Test helper / builder.
  factory Ev.at(int seconds, String t, [Map<String, dynamic> d = const {}]) =>
      Ev(seconds * 1000, t, Map<String, dynamic>.from(d));
}

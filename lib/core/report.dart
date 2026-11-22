import 'dart:convert';

import 'analyzer.dart';
import 'events.dart';
import 'i18n.dart';
import 'sessions.dart';

String two(int n) => n.toString().padLeft(2, '0');
String fmtTime(DateTime t) => '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

String outcomeLabel(Outcome o) => switch (o) {
      Outcome.ok => tr('OK', 'OK'),
      Outcome.slow => tr('Lentă', 'Slow'),
      Outcome.retry => tr('Cu reîncercări', 'With retries'),
      Outcome.drop => tr('Întreruptă', 'Dropped'),
      Outcome.fail => tr('Eșuată', 'Failed'),
      Outcome.wired => tr('Pe cablu', 'Wired'),
      Outcome.ongoing => tr('În curs', 'In progress'),
    };

/// Plain-text report: summary, causes, every drive and the raw journal.
String buildReport({
  required Map<String, dynamic> status,
  required Diagnosis d,
  required List<Session> sessions,
  required List<Ev> events,
  required List<String> sysLog,
}) {
  final b = StringBuffer();
  b.writeln('Nauto report — ${fmtTime(DateTime.now())}');
  b.writeln('Phone: ${status['model']} · Android ${status['android']}');
  b.writeln('Android Auto: ${status['aaVer']} · AA battery optimized: ${status['aaOpt']} · Nauto optimized: ${status['selfOpt']}');
  b.writeln('Adapter prefix: ${status['prefix']} · bonded: ${status['bonded']}');
  b.writeln('Perms: bt=${status['permBt']} loc=${status['permLoc']} bgLoc=${status['permBgLoc']} logs=${status['permLogs']}');
  b.writeln();
  b.writeln('== ${d.headline}');
  b.writeln('Drives: ${d.total}, ok: ${d.ok}, problems: ${d.bad}, median time-to-connect: ${d.medianTtc ?? '-'} s');
  b.writeln();
  for (final f in d.findings) {
    b.writeln('[${f.kind.name} · ${f.level} · ${f.score.toStringAsFixed(2)}] ${f.title}');
    b.writeln('  ${f.detail}');
    if (f.evidence.isNotEmpty) b.writeln('  > ${f.evidence}');
    for (final x in f.fixes) {
      b.writeln('  - $x');
    }
  }
  b.writeln();
  b.writeln('== Drives');
  for (final s in sessions) {
    b.writeln('${fmtTime(s.startTime)}  ${outcomeLabel(s.outcome).padRight(14)} ttc=${s.ttc ?? '-'}s retries=${s.retries} '
        'gaps=${s.gaps} drops=${s.drops.map((x) => x.adapterGone ? 'P' : 'L').join()} wifiSeen=${s.dongleWifiSeen} '
        'cyclesWifi=${s.cycles.map((c) => c.wifi ? 'W' : 'B').join()} home=${s.homeWifi ?? '-'} otherBt=${s.otherBt.join('|')} '
        'saver=${s.saver} idle=${s.idle} screenOff=${s.screenOff} rssi=${s.minRssi ?? '-'} freq=${s.freq ?? '-'} '
        'bat=${s.battery ?? '-'} aa=${s.aaVer ?? '-'} marks=${s.marks} wired=${s.wired} '
        'gh(socket=${s.ghSocket} noData=${s.ghNoData} noHfp=${s.ghNoHfp})');
  }
  b.writeln();
  b.writeln('== Journal (last 14 days)');
  final since = DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch;
  for (final e in events.where((e) => e.ts >= since)) {
    b.writeln('${fmtTime(e.time)} ${e.t} ${jsonEncode(e.d)}');
  }
  if (sysLog.isNotEmpty) {
    b.writeln();
    b.writeln('== System log (advanced mode, last ${sysLog.length} lines)');
    for (final l in sysLog) {
      b.writeln(l);
    }
  }
  return b.toString();
}

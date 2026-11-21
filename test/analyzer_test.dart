import 'package:flutter_test/flutter_test.dart';
import 'package:nauto/core/analyzer.dart';
import 'package:nauto/core/events.dart';
import 'package:nauto/core/sessions.dart';

const dongle = {'dev': 'AAWireless-1234', 'dongle': true};

List<Ev> drive(int t0, {bool loop = false, bool home = false, bool drop = false}) {
  final e = <Ev>[];
  if (home) e.add(Ev.at(t0 - 10, 'wifi', {'on': true, 'ssid': 'Acasa', 'net': true, 'inet': true, 'id': 'h$t0'}));
  e.add(Ev.at(t0, 'bt', {...dongle, 'on': true}));
  var t = t0;
  if (loop) {
    e.add(Ev.at(t + 5, 'wifi', {'on': true, 'ssid': '?', 'net': false, 'inet': false, 'id': 'w$t0'}));
    e.add(Ev.at(t + 30, 'bt', {...dongle, 'on': false}));
    e.add(Ev.at(t + 31, 'wifi', {'on': false, 'ssid': '?', 'id': 'w$t0'}));
    e.add(Ev.at(t + 50, 'bt', {...dongle, 'on': true}));
    t += 50;
  }
  e.add(Ev.at(t + 5, 'wifi', {'on': true, 'ssid': '?', 'net': false, 'inet': false, 'id': 'x$t0'}));
  if (home) e.add(Ev.at(t + 6, 'wifi', {'on': false, 'ssid': 'Acasa', 'id': 'h$t0'}));
  e.add(Ev.at(t + 20, 'aa', {'type': 2}));
  if (drop) {
    e.add(Ev.at(t + 300, 'aa', {'type': 0}));
    e.add(Ev.at(t + 301, 'bt', {...dongle, 'on': false}));
    e.add(Ev.at(t + 330, 'bt', {...dongle, 'on': true}));
    e.add(Ev.at(t + 350, 'aa', {'type': 2}));
  }
  e.add(Ev.at(t + 1200, 'aa', {'type': 0}));
  e.add(Ev.at(t + 1202, 'bt', {...dongle, 'on': false}));
  e.add(Ev.at(t + 1203, 'wifi', {'on': false, 'ssid': '?', 'id': 'x$t0'}));
  return e;
}

List<Session> build(List<Ev> evs) =>
    SessionBuilder().build(evs, nowMs: evs.last.ts + 10000 * 1000);

void main() {
  test('clean drives are OK and the car turning off is not a drop', () {
    final evs = [for (var i = 0; i < 4; i++) ...drive(10000 + i * 3600)];
    final s = build(evs);
    expect(s.length, 4);
    expect(s.every((x) => x.outcome == Outcome.ok), isTrue);
    expect(s.first.ttc, 20);
    final d = Analyzer.run(s, phone: const PhoneState(logs: true));
    expect(d.bad, 0);
    expect(d.findings.where((f) => f.kind == Kind.cause), isEmpty);
  });

  test('retries that got past Wi-Fi point at the car side', () {
    final evs = [
      for (var i = 0; i < 4; i++) ...drive(10000 + i * 3600, loop: true),
      for (var i = 4; i < 6; i++) ...drive(10000 + i * 3600),
    ];
    final s = build(evs);
    expect(s.length, 6);
    expect(s.where((x) => x.outcome == Outcome.retry).length, 4);
    expect(s.firstWhere((x) => x.retries > 0).gaps, [20]);
    final d = Analyzer.run(s);
    final causes = d.findings.where((f) => f.kind == Kind.cause).toList();
    expect(causes.first.id, 'car_side');
  });

  test('home Wi-Fi at start is detected as a factor', () {
    final evs = [
      for (var i = 0; i < 3; i++) ...drive(10000 + i * 3600, loop: true, home: true),
      for (var i = 3; i < 6; i++) ...drive(10000 + i * 3600),
    ];
    final d = Analyzer.run(build(evs));
    expect(d.findings.any((f) => f.id == 'home_wifi'), isTrue);
  });

  test('a mid-drive drop with the adapter gone is a power drop', () {
    final evs = [
      for (var i = 0; i < 2; i++) ...drive(10000 + i * 3600, drop: true),
      for (var i = 2; i < 4; i++) ...drive(10000 + i * 3600),
    ];
    final s = build(evs);
    expect(s.where((x) => x.outcome == Outcome.drop).length, 2);
    expect(s.firstWhere((x) => x.drops.isNotEmpty).drops.first.adapterGone, isTrue);
    final d = Analyzer.run(s);
    expect(d.findings.any((f) => f.id == 'drop_power'), isTrue);
  });

  test('journal parsing skips broken lines', () {
    final evs = Ev.parse('{"ts":2000,"t":"bt","on":true}\n{"ts":1000,"t":"aa","type":2}\n{broken');
    expect(evs.length, 2);
    expect(evs.first.isProjection, isTrue);
  });
}

import 'dart:io';

import 'package:flutter/services.dart';

import 'events.dart';

/// Talks to the Kotlin side (MainActivity / MonitorService).
class Native {
  static const _ch = MethodChannel('nauto/native');

  static Future<Map<String, dynamic>> status() async {
    try {
      final m = await _ch.invokeMethod<Map>('status');
      return Map<String, dynamic>.from(m ?? {});
    } catch (_) {
      return {};
    }
  }

  static Future<void> call(String method, [Map<String, dynamic>? args]) async {
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {}
  }

  static Future<String?> save(String name, String text) async {
    try {
      return await _ch.invokeMethod<String>('save', {'name': name, 'text': text});
    } catch (_) {
      return null;
    }
  }

  /// Journal written by the monitor (older file first).
  static Future<List<Ev>> events(String filesDir) async {
    final buf = StringBuffer();
    for (final n in ['events.1.jsonl', 'events.jsonl']) {
      final f = File('$filesDir/$n');
      if (await f.exists()) buf.write(await f.readAsString());
    }
    return Ev.parse(buf.toString());
  }

  /// Last lines of the system log stream (advanced mode).
  static final _key = RegExp(r'GH\.ConnLogger|CAR\.GAL|CAR\.SETUP|CAR\.WIFI|CAR\.BT|[Ww]ireless|wpa_supplicant: .*(CTRL-EVENT|reason)');

  static Future<List<String>> sysLog(String filesDir, {int max = 3000}) async {
    final lines = <String>[];
    for (final n in ['sys.1.log', 'sys.log']) {
      final f = File('$filesDir/$n');
      if (await f.exists()) lines.addAll(await f.readAsLines());
    }
    // Every Android Auto connection step from the whole log, then the recent tail.
    final keyLines = lines.where(_key.hasMatch).toList();
    final key = keyLines.length > 6000 ? keyLines.sublist(keyLines.length - 6000) : keyLines;
    final tail = lines.length > max ? lines.sublist(lines.length - max) : lines;
    final seen = key.toSet();
    return [...key, '----- tail -----', ...tail.where((l) => !seen.contains(l))];
  }
}

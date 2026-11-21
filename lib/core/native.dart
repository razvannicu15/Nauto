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
  static Future<List<String>> sysLog(String filesDir, {int max = 3000}) async {
    final lines = <String>[];
    for (final n in ['sys.1.log', 'sys.log']) {
      final f = File('$filesDir/$n');
      if (await f.exists()) lines.addAll(await f.readAsLines());
    }
    return lines.length > max ? lines.sublist(lines.length - max) : lines;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'analyzer.dart';
import 'events.dart';
import 'i18n.dart';
import 'native.dart';
import 'sessions.dart';

/// Settings + everything read from the monitor, shared by all screens.
class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  String language = 'ro'; // 'system' | 'ro' | 'en'
  String prefix = 'AAWireless';

  Map<String, dynamic> status = {};
  List<Ev> events = [];
  List<Session> sessions = [];
  Diagnosis? diagnosis;
  bool loading = false;

  File? _file;

  bool get running => status['running'] == true;
  bool get enabled => status['enabled'] == true;
  String get filesDir => (status['files'] as String?) ?? '';

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/settings.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        themeMode = ThemeMode.values.firstWhere((m) => m.name == j['theme'], orElse: () => ThemeMode.system);
        language = j['lang'] ?? 'ro';
        prefix = j['prefix'] ?? 'AAWireless';
      }
    } catch (_) {}
    setLanguage(language);
  }

  Future<void> save() async {
    setLanguage(language);
    notifyListeners();
    try {
      await _file?.writeAsString(jsonEncode({'theme': themeMode.name, 'lang': language, 'prefix': prefix}));
    } catch (_) {}
    await Native.call('setPrefs', {'prefix': prefix, 'lang': currentLang});
  }

  PhoneState get phone {
    final bonded = ((status['bonded'] as List?) ?? []).map((e) => e.toString()).toList();
    return PhoneState(
      selfOptimized: status['selfOpt'] == true,
      aaOptimized: status['aaOpt'] == true,
      logs: status['permLogs'] == true,
      bgLocation: status['permBgLoc'] != false,
      prefixBonded: bonded.isEmpty || bonded.any((n) => n.toLowerCase().startsWith(prefix.toLowerCase())),
    );
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    status = await Native.status();
    if (filesDir.isNotEmpty) {
      events = await Native.events(filesDir);
    }
    sessions = SessionBuilder(prefix: prefix).build(events).reversed.toList();
    diagnosis = Analyzer.run(sessions, phone: phone);
    loading = false;
    notifyListeners();
  }

  Future<void> setMonitoring(bool on) async {
    await Native.call('setPrefs', {'prefix': prefix, 'lang': currentLang});
    await Native.call(on ? 'start' : 'stop');
    await Future.delayed(const Duration(milliseconds: 600));
    await refresh();
  }
}

final app = AppState();

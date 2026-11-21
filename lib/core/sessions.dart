import 'events.dart';

/// How a connection attempt went.
enum Outcome { ok, slow, retry, drop, fail, ongoing }

/// A failed try before Android Auto started: the adapter connected over
/// Bluetooth, then disappeared again.
class Cycle {
  Cycle(this.start);
  final int start;
  int? end;

  /// The phone joined the adapter's Wi-Fi during this try.
  bool wifi = false;
}

/// Android Auto stopped while driving.
class Drop {
  Drop(this.ts);
  final int ts;
  bool recovered = false;

  /// The adapter vanished from Bluetooth at the same moment (lost power / rebooted).
  bool adapterGone = false;
}

/// One drive: from the adapter showing up until it has been gone for 3 min.
class Session {
  Session(this.start);

  final int start;
  int end = 0;
  bool open = true;
  final List<Ev> events = [];

  int? firstBt;
  int? firstAa;
  int? ttcNative;
  final List<Cycle> cycles = [];
  final List<int> gaps = []; // seconds the adapter was gone between tries
  final List<Drop> drops = [];
  int marks = 0;

  // Context
  String? homeWifi; // phone was on an internet Wi-Fi when the attempt began
  bool saver = false;
  bool idle = false;
  bool screenOff = false;
  bool plugged = false;
  int? battery;
  String? aaVer;
  bool aaOptimized = false;
  final Set<String> otherBt = {};
  int? minRssi;
  int? freq;
  bool dongleWifiSeen = false;
  int supplicantErrors = 0;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(start);

  /// Seconds from the adapter appearing to the car screen showing Android Auto.
  int? get ttc {
    if (ttcNative != null) return ttcNative;
    if (firstAa == null) return null;
    return ((firstAa! - (firstBt ?? start)) / 1000).round();
  }

  int get retries => cycles.length;
  int get durationSec => ((end - start) / 1000).round();

  Outcome get outcome {
    if (firstAa == null) return open ? Outcome.ongoing : Outcome.fail;
    if (drops.isNotEmpty) return Outcome.drop;
    if (retries > 0) return Outcome.retry;
    if ((ttc ?? 0) > 60) return Outcome.slow;
    return Outcome.ok;
  }

  bool get bad => (outcome != Outcome.ok && outcome != Outcome.ongoing) || marks > 0;
  bool get finished => outcome != Outcome.ongoing;
}

class SessionBuilder {
  SessionBuilder({this.prefix = 'AAWireless'});

  final String prefix;
  static const gapMs = 180 * 1000;

  bool _isDongleSsid(String? s) =>
      s != null && s.toLowerCase().contains(prefix.toLowerCase());

  /// The adapter's Wi-Fi: its name matches, or it is a local network without internet.
  bool isDongleWifi(Ev e) {
    if (_isDongleSsid(e.ssid)) return true;
    return e.t == 'wifi' && e.d['inet'] == false;
  }

  List<Session> build(List<Ev> evs, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final out = <Session>[];

    // Global phone state while walking the journal.
    final wifiNets = <String, Ev>{}; // network id -> last 'wifi on' event
    final otherConnected = <String>{};
    var saver = false, idle = false, screenOn = true, plugged = false;
    int? bat;
    String? aaVer;
    var aaOpt = false;

    Session? cur;
    var dongleOn = false;
    var projection = false;
    int? idleSince; // both adapter and projection gone since
    Cycle? cycle;
    int? dongleOffAt;

    void close(int at) {
      final s = cur!;
      s.end = at;
      s.open = false;
      _finish(s);
      cur = null;
      cycle = null;
      idleSince = null;
    }

    Session open(Ev e) {
      final s = Session(e.ts);
      s.saver = saver;
      s.idle = idle;
      s.screenOff = !screenOn;
      s.plugged = plugged;
      s.battery = bat;
      s.aaVer = aaVer;
      s.aaOptimized = aaOpt;
      s.otherBt.addAll(otherConnected);
      for (final w in wifiNets.values) {
        if (w.d['net'] == true && !isDongleWifi(w)) s.homeWifi = w.ssid ?? '?';
      }
      out.add(s);
      return s;
    }

    for (final e in evs) {
      // Close a session that has been quiet long enough.
      if (cur != null && idleSince != null && e.ts - idleSince! > gapMs) {
        close(idleSince!);
      }

      // --- global state
      switch (e.t) {
        case 'wifi':
          final id = (e.d['id'] ?? e.ssid ?? '?').toString();
          if (e.on) {
            wifiNets[id] = e;
          } else {
            wifiNets.remove(id);
          }
        case 'saver':
          saver = e.on;
        case 'idle':
          idle = e.on;
        case 'screen':
          screenOn = e.on;
        case 'plug':
          plugged = e.on;
        case 'info':
          aaVer = e.d['aa_ver'] as String? ?? aaVer;
          aaOpt = e.d['aa_opt'] == true;
        case 'bt':
          if (!e.dongle && e.dev != null) {
            if (e.on) {
              otherConnected.add(e.dev!);
            } else {
              otherConnected.remove(e.dev!);
            }
          }
      }
      final b = e.intOf('bat');
      if (b != null && b >= 0) bat = b;

      // --- session state machine
      final dongleEvent = e.t == 'bt' && e.dongle;
      if (cur == null && e.t == 'mark' && out.isNotEmpty && e.ts - out.last.end < 20 * 60 * 1000) {
        // Flagged right after a drive (e.g. once parked): it belongs to that drive.
        out.last.marks++;
        out.last.events.add(e);
        continue;
      }
      if (cur == null) {
        // A flag with nothing going on = the adapter never reached the phone.
        if ((dongleEvent && e.on) || e.isProjection || e.t == 'mark') {
          cur = open(e);
          dongleOffAt = null;
        } else {
          continue;
        }
      }
      final s = cur!;
      s.events.add(e);

      if (dongleEvent) {
        if (e.on) {
          dongleOn = true;
          s.firstBt ??= e.ts;
          if (dongleOffAt != null) s.gaps.add(((e.ts - dongleOffAt!) / 1000).round());
          dongleOffAt = null;
          if (s.firstAa == null) cycle = Cycle(e.ts);
        } else {
          dongleOn = false;
          dongleOffAt = e.ts;
          if (s.firstAa == null && cycle != null) {
            cycle!.end = e.ts;
            s.cycles.add(cycle!);
            cycle = null;
          }
          // Projection lost together with the adapter -> mark the drop.
          if (s.drops.isNotEmpty && (e.ts - s.drops.last.ts).abs() <= 8000) {
            s.drops.last.adapterGone = true;
          }
        }
      } else if (e.t == 'aa') {
        final p = e.isProjection;
        if (p && !projection) {
          if (s.firstAa == null) {
            s.firstAa = e.ts;
            s.ttcNative = e.intOf('ttc');
            cycle = null;
          } else if (s.drops.isNotEmpty) {
            s.drops.last.recovered = true;
          }
        } else if (!p && projection) {
          final d = Drop(e.ts);
          // Adapter already gone a moment ago?
          if (dongleOffAt != null && (e.ts - dongleOffAt!).abs() <= 8000) d.adapterGone = true;
          s.drops.add(d);
        }
        projection = p;
      } else if (e.t == 'wifi' || e.t == 'wifi_s') {
        if (isDongleWifi(e)) {
          if ((e.t == 'wifi' && e.on) || e.t == 'wifi_s') {
            s.dongleWifiSeen = true;
            if (s.firstAa == null && cycle != null) cycle!.wifi = true;
            final r = e.intOf('rssi');
            if (r != null && r > -127 && r < 0) s.minRssi = s.minRssi == null || r < s.minRssi! ? r : s.minRssi;
            final f = e.intOf('freq');
            if (f != null && f > 0) s.freq = f;
          }
        } else if (s.firstAa == null && e.t == 'wifi' && e.on && e.d['net'] == true) {
          s.homeWifi ??= e.ssid ?? '?';
        }
      } else if (e.t == 'supp') {
        if (e.d['err'] != null) s.supplicantErrors++;
      } else if (e.t == 'mark') {
        s.marks++;
      } else if (s.firstAa == null) {
        switch (e.t) {
          case 'saver':
            if (e.on) s.saver = true;
          case 'idle':
            if (e.on) s.idle = true;
          case 'bt':
            if (e.on && e.dev != null) s.otherBt.add(e.dev!);
        }
      }

      final active = dongleOn || projection;
      if (active) {
        idleSince = null;
      } else {
        idleSince ??= e.ts;
      }
    }

    if (cur != null && idleSince != null && now - idleSince! > gapMs) {
      close(idleSince!);
    } else if (cur != null) {
      cur!.end = evs.isEmpty ? now : evs.last.ts;
      _finish(cur!);
    }
    return out;
  }

  void _finish(Session s) {
    // The last projection stop at the end of a drive is the car turning off,
    // not a drop: it is followed by the adapter leaving and nothing else.
    if (!s.open && s.drops.isNotEmpty) {
      final last = s.drops.last;
      final tail = s.events.where((e) => e.ts > last.ts);
      final reconnects = tail.any((e) => e.isProjection);
      final adapterStayed = !tail.any((e) => e.t == 'bt' && e.dongle && !e.on) ||
          tail.where((e) => e.t == 'bt' && e.dongle && !e.on).first.ts - last.ts > 30000;
      if (!reconnects && !adapterStayed) s.drops.removeLast();
    }
  }
}

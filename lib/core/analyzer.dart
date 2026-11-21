import 'i18n.dart';
import 'sessions.dart';

enum Kind { cause, check }

class Finding {
  Finding({
    required this.id,
    required this.kind,
    required this.score,
    required this.title,
    required this.detail,
    required this.fixes,
    this.evidence = '',
  });

  final String id;
  final Kind kind;

  /// 0..1 — how strongly the recorded data points at this.
  final double score;
  final String title;
  final String detail;
  final List<String> fixes;
  final String evidence;

  String get level => score >= 0.6
      ? tr('mare', 'high')
      : score >= 0.35
          ? tr('medie', 'medium')
          : tr('mică', 'low');
}

class Diagnosis {
  Diagnosis({
    required this.total,
    required this.ok,
    required this.bad,
    required this.medianTtc,
    required this.findings,
    required this.headline,
    required this.enough,
  });

  final int total, ok, bad;
  final int? medianTtc;
  final List<Finding> findings;
  final String headline;

  /// Enough drives recorded to trust the causes.
  final bool enough;
}

/// Phone state the analyzer can also use (from Native.status()).
class PhoneState {
  const PhoneState({
    this.selfOptimized = false,
    this.aaOptimized = false,
    this.logs = false,
    this.bgLocation = true,
    this.prefixBonded = true,
  });
  final bool selfOptimized, aaOptimized, logs, bgLocation, prefixBonded;
}

class Analyzer {
  static const minDrives = 3;
  static const goodDrives = 8;

  static Diagnosis run(List<Session> sessions, {PhoneState phone = const PhoneState()}) {
    final all = sessions.where((s) => s.finished).toList();
    final bad = all.where((s) => s.bad).toList();
    final ttcs = all.map((s) => s.ttc).whereType<int>().toList()..sort();
    final median = ttcs.isEmpty ? null : ttcs[ttcs.length ~/ 2];
    final f = <Finding>[];

    if (bad.isNotEmpty) {
      _patterns(all, bad, f);
      _factors(all, bad, f);
    }
    _checks(phone, f);

    f.sort((a, b) {
      if (a.kind != b.kind) return a.kind.index.compareTo(b.kind.index);
      return b.score.compareTo(a.score);
    });

    final enough = all.length >= minDrives;
    String headline;
    if (all.isEmpty) {
      headline = tr('Încă nu am înregistrat nicio conectare. Pornește monitorizarea și mergi cu mașina.',
          'No connection recorded yet. Turn monitoring on and drive.');
    } else if (bad.isEmpty) {
      headline = tr('Toate cele ${all.length} conectări au mers bine.', 'All ${all.length} connections went fine.');
    } else if (!enough) {
      headline = tr('${bad.length} din ${all.length} conectări au avut probleme. Mai am nevoie de câteva drumuri.',
          '${bad.length} of ${all.length} connections had problems. I need a few more drives.');
    } else {
      final top = f.where((x) => x.kind == Kind.cause).toList();
      headline = top.isEmpty
          ? tr('${bad.length} din ${all.length} conectări au avut probleme, fără o cauză clară încă.',
              '${bad.length} of ${all.length} connections had problems, no clear cause yet.')
          : tr('${bad.length} din ${all.length} conectări au avut probleme. Cauza cea mai probabilă: ${top.first.title.toLowerCase()}.',
              '${bad.length} of ${all.length} connections had problems. Most likely cause: ${top.first.title.toLowerCase()}.');
    }

    return Diagnosis(
      total: all.length,
      ok: all.length - bad.length,
      bad: bad.length,
      medianTtc: median,
      findings: f,
      headline: headline,
      enough: enough,
    );
  }

  // ---------------------------------------------------------------- patterns

  static List<String> get carFixes => [
        tr('Folosește un cablu scurt de date, de calitate (max. 30 cm, USB-A → USB-C), fără prelungitor sau hub.',
            'Use a short, good-quality data cable (max 30 cm, USB-A → USB-C), no extension or hub.'),
        tr('Dacă mașina are mai multe porturi USB, mută adaptorul în portul marcat pentru telefon/date.',
            'If the car has several USB ports, move the adapter to the one marked for phone/data.'),
        tr('În aplicația AAWireless → Advanced: activează Passthrough câteva zile (setările DPI nu merg cu el).',
            'In the AAWireless app → Advanced: turn Passthrough on for a few days (DPI settings don\'t work with it).'),
        tr('Test: pornește mașina, așteaptă ecranul complet pornit, abia apoi bagă adaptorul.',
            'Test: start the car, wait for the screen to fully boot, only then plug the adapter in.'),
        tr('Actualizează firmware-ul AAWireless (OTA din aplicație, cu adaptorul la o priză) și cere la dealer update pentru unitatea multimedia MG.',
            'Update the AAWireless firmware (OTA from the app, adapter on a wall socket) and ask the MG dealer for a head unit update.'),
      ];

  static List<String> get phoneWifiFixes => [
        tr('Setări → Conexiuni → Wi-Fi → ⋮ → Intelligent Wi-Fi: oprește „Comutare la date mobile” și „Mod economisire energie Wi-Fi”.',
            'Settings → Connections → Wi-Fi → ⋮ → Intelligent Wi-Fi: turn off “Switch to mobile data” and “Wi-Fi power saving mode”.'),
        tr('Uită rețeaua Wi-Fi AAWireless-xxxx și conectează-te din nou doar din Bluetooth.',
            'Forget the AAWireless-xxxx Wi-Fi network and reconnect only from Bluetooth.'),
        tr('Android Auto → Stocare → Golește memoria cache.', 'Android Auto → Storage → Clear cache.'),
        tr('Nu opri Wi-Fi-ul din panoul rapid sau din rutine.', 'Don\'t turn Wi-Fi off from Quick Settings or routines.'),
      ];

  static List<String> get batteryFixes => [
        tr('Android Auto → Baterie → Nerestricționat.', 'Android Auto → Battery → Unrestricted.'),
        tr('Setări → Baterie → Limite utilizare în fundal → „Aplicații care nu intră niciodată în repaus”: adaugă Android Auto și Nauto.',
            'Settings → Battery → Background usage limits → “Never sleeping apps”: add Android Auto and Nauto.'),
        tr('Nu porni economizorul de baterie în mașină.', 'Don\'t use battery saver in the car.'),
      ];

  static void _patterns(List<Session> all, List<Session> bad, List<Finding> f) {
    final cycles = bad.expand((s) => s.cycles).toList();
    final wifiVisible = all.any((s) => s.dongleWifiSeen);
    final retrySessions = bad.where((s) => s.retries > 0 || s.outcome == Outcome.fail).toList();

    if (cycles.length >= 2) {
      final share = retrySessions.length / all.length;
      if (wifiVisible) {
        final withWifi = cycles.where((c) => c.wifi).length;
        final ratio = withWifi / cycles.length;
        if (ratio >= 0.6) {
          f.add(Finding(
            id: 'car_side',
            kind: Kind.cause,
            score: (0.45 + 0.5 * ratio * share.clamp(0.2, 1.0)).clamp(0, 1).toDouble(),
            title: tr('Legătura adaptor ↔ mașină (USB)', 'Adapter ↔ car link (USB)'),
            detail: tr(
                'Telefonul ajunge la adaptor (Bluetooth și Wi-Fi), dar adaptorul nu reușește să pornească Android Auto pe ecranul mașinii și repornește. Asta e exact bucla verde intermitent → albastru intermitent → din nou verde.',
                'The phone reaches the adapter (Bluetooth and Wi-Fi), but the adapter fails to start Android Auto on the car screen and restarts. That is exactly the blinking green → blinking blue → green again loop.'),
            fixes: carFixes,
            evidence: tr('$withWifi din ${cycles.length} încercări eșuate au trecut de Wi-Fi.',
                '$withWifi of ${cycles.length} failed tries got past Wi-Fi.'),
          ));
        } else if (ratio <= 0.4) {
          f.add(Finding(
            id: 'phone_wifi',
            kind: Kind.cause,
            score: (0.45 + 0.5 * (1 - ratio) * share.clamp(0.2, 1.0)).clamp(0, 1).toDouble(),
            title: tr('Telefonul nu intră pe Wi-Fi-ul adaptorului', 'Phone doesn\'t join the adapter\'s Wi-Fi'),
            detail: tr(
                'Bluetooth-ul se conectează, dar telefonul nu trece pe Wi-Fi-ul adaptorului și adaptorul renunță. Problema e pe telefon (Wi-Fi Samsung), nu în mașină.',
                'Bluetooth connects, but the phone doesn\'t switch to the adapter\'s Wi-Fi and the adapter gives up. The problem is on the phone (Samsung Wi-Fi), not in the car.'),
            fixes: phoneWifiFixes,
            evidence: tr('${cycles.length - withWifi} din ${cycles.length} încercări eșuate s-au oprit înainte de Wi-Fi.',
                '${cycles.length - withWifi} of ${cycles.length} failed tries stopped before Wi-Fi.'),
          ));
        }
      }

      // Adapter reboots between tries, seen from Bluetooth alone.
      final reboots = bad.expand((s) => s.gaps).where((g) => g >= 5 && g <= 120).length;
      if (reboots >= 2 && !f.any((x) => x.id == 'car_side' || x.id == 'phone_wifi')) {
        f.add(Finding(
          id: 'reboot_loop',
          kind: Kind.cause,
          score: (0.35 + 0.4 * share).clamp(0, 0.8).toDouble(),
          title: tr('Adaptorul repornește între încercări', 'The adapter restarts between tries'),
          detail: tr(
              'Adaptorul dispare din Bluetooth și revine după câteva secunde, înainte ca Android Auto să pornească. Dacă înainte de repornire LED-ul era albastru intermitent, cauza e legătura cu mașina (USB). Dacă era verde intermitent, e telefonul. Activează modul avansat (jurnale sistem) ca să aflu sigur.',
              'The adapter vanishes from Bluetooth and returns a few seconds later, before Android Auto starts. If the LED was blinking blue before the restart, the cause is the car link (USB). If it was blinking green, it\'s the phone. Turn on advanced mode (system logs) so I can tell for sure.'),
          fixes: carFixes,
          evidence: tr('$reboots reporniri în ${retrySessions.length} drumuri.', '$reboots restarts over ${retrySessions.length} drives.'),
        ));
      }
    }

    // Drops while driving.
    final drops = bad.expand((s) => s.drops).toList();
    if (drops.isNotEmpty) {
      final power = drops.where((d) => d.adapterGone).length;
      final link = drops.length - power;
      if (power >= 1) {
        f.add(Finding(
          id: 'drop_power',
          kind: Kind.cause,
          score: (0.4 + 0.15 * power).clamp(0, 0.95).toDouble(),
          title: tr('Adaptorul pierde alimentarea în mers', 'The adapter loses power while driving'),
          detail: tr(
              'Android Auto s-a oprit exact când adaptorul a dispărut: mașina a resetat portul USB. Pe MG EHS asta apare des la semnalizare sau la meniul de climă — e o problemă a unității multimedia, nu a telefonului.',
              'Android Auto stopped exactly when the adapter vanished: the car reset its USB port. On the MG EHS this often happens when using the indicators or the climate menu — it\'s a head unit problem, not the phone.'),
          fixes: [carFixes[0], carFixes[1], carFixes[4]],
          evidence: tr('$power întreruperi cu adaptorul dispărut.', '$power drops with the adapter gone.'),
        ));
      }
      if (link >= 1) {
        f.add(Finding(
          id: 'drop_link',
          kind: Kind.cause,
          score: (0.35 + 0.15 * link).clamp(0, 0.9).toDouble(),
          title: tr('Legătura wireless cade în mers', 'The wireless link drops while driving'),
          detail: tr(
              'Android Auto s-a oprit, dar adaptorul a rămas alimentat: s-a pierdut legătura Wi-Fi dintre telefon și adaptor.',
              'Android Auto stopped while the adapter stayed powered: the Wi-Fi link between phone and adapter was lost.'),
          fixes: [
            tr('În aplicația AAWireless → Advanced → Wi-Fi channel: încearcă 36, apoi 149.',
                'In the AAWireless app → Advanced → Wi-Fi channel: try 36, then 149.'),
            tr('Ține telefonul pe suport, nu în buzunar sau în geantă.', 'Keep the phone in a mount, not in a pocket or bag.'),
            phoneWifiFixes[0],
          ],
          evidence: tr('$link întreruperi cu adaptorul alimentat.', '$link drops with the adapter powered.'),
        ));
      }
    }

    // Slow start without retries.
    final slow = all.where((s) => s.outcome == Outcome.slow).length;
    if (slow >= 2 && slow / all.length >= 0.25) {
      f.add(Finding(
        id: 'slow',
        kind: Kind.cause,
        score: (0.3 + 0.5 * slow / all.length).clamp(0, 0.8).toDouble(),
        title: tr('Pornire lentă, fără erori', 'Slow start, no errors'),
        detail: tr('Se conectează din prima, dar durează peste un minut. De obicei telefonul „doarme” și pornește greu Wi-Fi-ul și Android Auto.',
            'It connects first time but takes over a minute. Usually the phone is asleep and slow to wake Wi-Fi and Android Auto.'),
        fixes: [...batteryFixes, phoneWifiFixes[0]],
        evidence: tr('$slow drumuri lente.', '$slow slow drives.'),
      ));
    }
  }

  // ----------------------------------------------------------------- factors

  /// Adds a finding when a condition makes problems clearly more likely.
  static void _factor(List<Session> all, List<Session> bad, List<Finding> out, bool Function(Session) has,
      {required String id,
      required String title,
      required String detail,
      required List<String> fixes,
      double weight = 1}) {
    final withF = all.where(has).toList();
    if (withF.isEmpty) return;
    final without = all.where((s) => !has(s)).toList();
    final badWith = withF.where((s) => s.bad).length;
    if (badWith < 2) return;
    final pWith = badWith / withF.length;
    final pWithout = without.isEmpty ? 0.0 : without.where((s) => s.bad).length / without.length;
    final lift = pWith - pWithout;
    if (lift < 0.25 && !(without.isEmpty && pWith >= 0.8)) return;
    final coverage = badWith / bad.length;
    out.add(Finding(
      id: id,
      kind: Kind.cause,
      score: ((0.25 + 0.45 * lift.clamp(0, 1) + 0.3 * coverage) * weight).clamp(0, 1).toDouble(),
      title: title,
      detail: detail,
      fixes: fixes,
      evidence: tr(
          'Cu asta: $badWith/${withF.length} cu probleme. Fără: ${without.where((s) => s.bad).length}/${without.length}.',
          'With it: $badWith/${withF.length} had problems. Without: ${without.where((s) => s.bad).length}/${without.length}.'),
    ));
  }

  static void _factors(List<Session> all, List<Session> bad, List<Finding> f) {
    _factor(all, bad, f, (s) => s.homeWifi != null,
        id: 'home_wifi',
        title: tr('Telefonul era pe Wi-Fi-ul de acasă', 'Phone was on home Wi-Fi'),
        detail: tr(
            'Problemele apar când telefonul e încă pe Wi-Fi-ul casei la pornirea mașinii (semnalul ajunge până la mașină). Android Auto trebuie să părăsească o rețea cu internet, iar Samsung uneori refuză sau revine.',
            'Problems happen when the phone is still on home Wi-Fi as the car starts (the signal reaches the car). Android Auto has to leave a network with internet, and Samsung sometimes refuses or switches back.'),
        fixes: [
          tr('Test câteva zile: la rețeaua de acasă dezactivează „Reconectare automată”, sau pornește mașina după ce ai ieșit din raza Wi-Fi.',
              'Test for a few days: turn off “Auto reconnect” for the home network, or start the car once you\'re out of Wi-Fi range.'),
          phoneWifiFixes[0],
        ]);

    // The other Bluetooth device seen most often in bad drives.
    final counts = <String, int>{};
    for (final s in bad) {
      for (final d in s.otherBt) {
        counts[d] = (counts[d] ?? 0) + 1;
      }
    }
    if (counts.isNotEmpty) {
      final top = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      _factor(all, bad, f, (s) => s.otherBt.contains(top),
          id: 'other_bt',
          title: tr('Alt dispozitiv Bluetooth: $top', 'Another Bluetooth device: $top'),
          detail: tr(
              '„$top” se conectează în același timp cu adaptorul și cele două se încurcă (apeluri, audio).',
              '“$top” connects at the same time as the adapter and the two get in each other\'s way (calls, audio).'),
          fixes: [
            tr('Dacă „$top” e Bluetooth-ul mașinii: pe telefon, la acest dispozitiv dezactivează „Apeluri” și „Audio” sau șterge asocierea — AAWireless preia apelurile.',
                'If “$top” is the car\'s Bluetooth: on the phone, turn off “Calls” and “Audio” for it or unpair it — AAWireless handles calls.'),
            tr('Dacă e ceas sau căști: testează câteva drumuri fără ele.', 'If it\'s a watch or earbuds: test a few drives without them.'),
          ]);
    }

    _factor(all, bad, f, (s) => s.saver || s.idle,
        id: 'battery',
        title: tr('Economisirea bateriei', 'Battery saving'),
        detail: tr('Problemele apar când telefonul e în economizor sau în repaus profund (Doze).',
            'Problems happen when the phone is in battery saver or deep sleep (Doze).'),
        fixes: batteryFixes);

    _factor(all, bad, f, (s) => s.screenOff,
        id: 'screen_off',
        title: tr('Telefonul blocat, cu ecranul stins', 'Phone locked, screen off'),
        detail: tr('Cu ecranul stins conectarea eșuează mai des: Samsung amână Wi-Fi-ul și aplicațiile din fundal.',
            'With the screen off the connection fails more often: Samsung delays Wi-Fi and background apps.'),
        fixes: [...batteryFixes, phoneWifiFixes[0]],
        weight: 0.9);

    _factor(all, bad, f, (s) => s.minRssi != null && s.minRssi! < -70,
        id: 'weak_signal',
        title: tr('Semnal Wi-Fi slab între telefon și adaptor', 'Weak Wi-Fi signal between phone and adapter'),
        detail: tr('Semnalul spre adaptor coboară sub -70 dBm în drumurile cu probleme.',
            'The signal to the adapter drops below -70 dBm on the problem drives.'),
        fixes: [
          tr('Ține telefonul pe suport, aproape de consolă; nu în buzunar sau în geantă.',
              'Keep the phone in a mount near the console; not in a pocket or bag.'),
          tr('În aplicația AAWireless → Advanced → Wi-Fi channel: încearcă 36, apoi 149.',
              'In the AAWireless app → Advanced → Wi-Fi channel: try 36, then 149.'),
        ]);

    _factor(all, bad, f, (s) => s.freq != null && s.freq! >= 5250 && s.freq! <= 5730,
        id: 'dfs',
        title: tr('Canal Wi-Fi DFS', 'DFS Wi-Fi channel'),
        detail: tr('Adaptorul folosește un canal 5 GHz de tip DFS, pe care telefonul trebuie să-l asculte înainte să transmită — întârzieri și căderi.',
            'The adapter uses a DFS 5 GHz channel the phone must listen to before transmitting — delays and drops.'),
        fixes: [
          tr('În aplicația AAWireless → Advanced → Wi-Fi channel: setează 36 sau 149.',
              'In the AAWireless app → Advanced → Wi-Fi channel: set 36 or 149.'),
        ]);

    _factor(all, bad, f, (s) => s.supplicantErrors > 0,
        id: 'wifi_auth',
        title: tr('Erori de autentificare Wi-Fi', 'Wi-Fi authentication errors'),
        detail: tr('Telefonul a primit erori la intrarea pe Wi-Fi-ul adaptorului.',
            'The phone got errors joining the adapter\'s Wi-Fi.'),
        fixes: [
          phoneWifiFixes[1],
          tr('Resetează adaptorul din aplicația AAWireless și împerechează din nou.',
              'Reset the adapter from the AAWireless app and pair again.'),
        ]);

    // Android Auto version.
    final versions = all.map((s) => s.aaVer).whereType<String>().toSet();
    if (versions.length >= 2) {
      for (final v in versions) {
        _factor(all, bad, f, (s) => s.aaVer == v,
            id: 'aa_ver_$v',
            title: tr('Versiunea Android Auto $v', 'Android Auto version $v'),
            detail: tr('Problemele au apărut mai ales cu această versiune de Android Auto.',
                'Problems appeared mostly with this Android Auto version.'),
            fixes: [
              tr('Verifică update în Magazin Play; dacă problema a apărut după update, dezinstalează actualizările Android Auto (revine la versiunea veche).',
                  'Check Play Store for an update; if it started after an update, uninstall Android Auto updates (rolls back).'),
            ]);
      }
    }
  }

  // ------------------------------------------------------------------ checks

  static void _checks(PhoneState p, List<Finding> f) {
    if (p.aaOptimized) {
      f.add(Finding(
        id: 'chk_aa_battery',
        kind: Kind.check,
        score: 0.5,
        title: tr('Android Auto are bateria optimizată', 'Android Auto is battery-optimized'),
        detail: tr('Sistemul poate opri Android Auto în fundal, chiar înainte de conectare.',
            'The system can stop Android Auto in the background, even before connecting.'),
        fixes: batteryFixes.take(2).toList(),
      ));
    }
    if (p.selfOptimized) {
      f.add(Finding(
        id: 'chk_self_battery',
        kind: Kind.check,
        score: 0.4,
        title: tr('Nauto poate fi oprit de sistem', 'Nauto may be stopped by the system'),
        detail: tr('Fără excepție de la optimizarea bateriei pot lipsi drumuri din jurnal.',
            'Without a battery exception, some drives may be missing from the journal.'),
        fixes: [tr('Acasă → Configurare → „Fără restricții de baterie”.', 'Home → Setup → “No battery restrictions”.')],
      ));
    }
    if (!p.logs) {
      f.add(Finding(
        id: 'chk_logs',
        kind: Kind.check,
        score: 0.2,
        title: tr('Modul avansat e oprit', 'Advanced mode is off'),
        detail: tr('Cu jurnalele de sistem văd și mesajele Android Auto și Wi-Fi, nu doar evenimentele.',
            'With system logs I also see Android Auto and Wi-Fi messages, not just events.'),
        fixes: [
          tr('Pe PC: rulează Nauto.bat → opțiunea [6] cu telefonul pe cablu.', 'On the PC: run Nauto.bat → option [6] with the phone on USB.'),
        ],
      ));
    }
    if (!p.prefixBonded) {
      f.add(Finding(
        id: 'chk_prefix',
        kind: Kind.check,
        score: 0.45,
        title: tr('Nu găsesc adaptorul în Bluetooth', 'Adapter not found in Bluetooth'),
        detail: tr('Niciun dispozitiv asociat nu începe cu numele setat. Verifică numele din Setări.',
            'No paired device starts with the configured name. Check the name in Settings.'),
        fixes: [tr('Setări → Numele adaptorului.', 'Settings → Adapter name.')],
      ));
    }
  }
}

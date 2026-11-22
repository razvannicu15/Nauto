import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/events.dart';
import '../core/i18n.dart';
import '../core/report.dart';
import '../core/sessions.dart';
import 'widgets.dart';

class DrivesPage extends StatelessWidget {
  const DrivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final list = app.sessions;
    if (list.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 120),
        Icon(Icons.directions_car_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Center(child: Text(tr('Niciun drum încă.', 'No drives yet.'))),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = list[i];
        final parts = <String>[
          if (s.ttc != null) tr('pornit în ${s.ttc}s', 'started in ${s.ttc}s'),
          if (s.retries > 0) tr('${s.retries} reîncercări', '${s.retries} retries'),
          if (s.drops.isNotEmpty) tr('${s.drops.length} întreruperi', '${s.drops.length} drops'),
          if (s.marks > 0) tr('marcat de tine', 'flagged by you'),
        ];
        return Card(
          child: ListTile(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DrivePage(session: s))),
            title: Text(fmtTime(s.startTime), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(parts.isEmpty ? tr('${s.durationSec ~/ 60} min', '${s.durationSec ~/ 60} min') : parts.join(' · ')),
            trailing: OutcomeChip(s.outcome),
          ),
        );
      },
    );
  }
}

/// Human-readable line for one journal event.
(IconData, String) describe(Ev e, SessionBuilder sb) {
  final dev = e.dev ?? '?';
  switch (e.t) {
    case 'bt':
      if (e.dongle) {
        return e.on
            ? (Icons.bluetooth_connected, tr('Adaptorul s-a conectat prin Bluetooth', 'Adapter connected over Bluetooth'))
            : (Icons.bluetooth_disabled, tr('Adaptorul a dispărut din Bluetooth', 'Adapter vanished from Bluetooth'));
      }
      return (Icons.bluetooth, e.on ? tr('Alt dispozitiv conectat: $dev', 'Other device connected: $dev') : tr('Deconectat: $dev', 'Disconnected: $dev'));
    case 'bt_prof':
      final st = switch (e.intOf('st')) { 2 => tr('conectat', 'connected'), 0 => tr('deconectat', 'disconnected'), _ => '…' };
      return (Icons.headset_mic_outlined, '${(e.d['p'] as String? ?? '').toUpperCase()} $dev: $st');
    case 'bt_req':
      return (Icons.bluetooth_searching, tr('Cerere de deconectare: $dev', 'Disconnect requested: $dev'));
    case 'bt_power':
      return (Icons.bluetooth, e.on ? tr('Bluetooth pornit', 'Bluetooth on') : tr('Bluetooth oprit', 'Bluetooth off'));
    case 'wifi':
      final dongle = sb.isDongleWifi(e);
      final name = dongle ? tr('Wi-Fi adaptor', 'Adapter Wi-Fi') : 'Wi-Fi ${e.ssid ?? '?'}';
      final extra = [
        if (e.intOf('rssi') != null && e.intOf('rssi')! > -127) '${e.intOf('rssi')} dBm',
        if (e.intOf('freq') != null && e.intOf('freq')! > 0) '${e.intOf('freq')} MHz',
        if (e.d['net'] == true) tr('cu internet', 'with internet'),
      ].join(' · ');
      return (
        e.on ? Icons.wifi : Icons.wifi_off,
        e.on ? '$name ${tr('conectat', 'connected')}${extra.isEmpty ? '' : ' ($extra)'}' : '$name ${tr('pierdut', 'lost')}'
      );
    case 'wifi_s':
      return (Icons.network_wifi_3_bar, 'Wi-Fi ${e.ssid ?? '?'} · ${e.intOf('rssi')} dBm · ${e.intOf('freq')} MHz · ${e.intOf('link')} Mbps');
    case 'wifi_power':
      return (Icons.wifi, e.on ? tr('Wi-Fi pornit', 'Wi-Fi on') : tr('Wi-Fi oprit', 'Wi-Fi off'));
    case 'supp':
      return (Icons.vpn_key_outlined, 'Wi-Fi: ${e.d['st']}${e.d['err'] != null ? ' · ${tr('eroare', 'error')} ${e.d['err']}' : ''}');
    case 'aa':
      final ttc = e.intOf('ttc');
      return e.isProjection
          ? (Icons.directions_car, tr('Android Auto pornit pe ecran${ttc != null ? ' (după ${ttc}s)' : ''}', 'Android Auto on screen${ttc != null ? ' (after ${ttc}s)' : ''}'))
          : (Icons.no_crash_outlined, tr('Android Auto oprit', 'Android Auto stopped'));
    case 'saver':
      return (Icons.battery_saver, e.on ? tr('Economizor baterie pornit', 'Battery saver on') : tr('Economizor oprit', 'Battery saver off'));
    case 'idle':
      return (Icons.bedtime_outlined, e.on ? tr('Telefonul a intrat în repaus (Doze)', 'Phone entered Doze') : tr('Telefonul a ieșit din repaus', 'Phone left Doze'));
    case 'screen':
      return (Icons.smartphone, e.on ? tr('Ecran aprins', 'Screen on') : tr('Ecran stins', 'Screen off'));
    case 'plug':
      return (Icons.power, e.on ? tr('Încărcare pornită', 'Charging') : tr('Încărcare oprită', 'Not charging'));
    case 'gh':
      final ev = e.d['e'] as String? ?? '';
      final txt = switch (ev) {
        'WIRELESS_WIFI_SOCKET_CONNECTED' => tr('Android Auto: conectat la adaptor', 'Android Auto: connected to the adapter'),
        'FRAMER_READ_IO_EXCEPTION_WITH_NO_DATA_RECEIVED' => tr('Android Auto: adaptorul n-a trimis nimic (mașina nu răspunde)', 'Android Auto: adapter sent nothing (car not answering)'),
        'WIRELESS_SETUP_FAILED_TO_START_NO_HFP_FROM_HU_PRESENCE' => tr('Android Auto: lipsă hands-free de la adaptor', 'Android Auto: no hands-free from the adapter'),
        'VERSION_NEGOTIATION_STARTED' => tr('Android Auto: mașina a răspuns', 'Android Auto: the car answered'),
        'WIRELESS_CONNECTED_WIFI' => tr('Android Auto: Wi-Fi adaptor conectat', 'Android Auto: adapter Wi-Fi connected'),
        'WIRELESS_WIFI_NETWORK_CONNECTION_LOST' => tr('Android Auto: Wi-Fi adaptor pierdut', 'Android Auto: adapter Wi-Fi lost'),
        _ => 'Android Auto: $ev',
      };
      return (Icons.terminal, txt);
    case 'mark':
      return (Icons.flag, tr('Ai marcat o problemă', 'You flagged a problem'));
    case 'info':
      return (Icons.info_outline, 'Android Auto ${e.d['aa_ver'] ?? '?'}');
    case 'svc':
      return (Icons.sensors, e.on ? tr('Monitorizare pornită', 'Monitoring started') : tr('Monitorizare oprită', 'Monitoring stopped'));
    case 'carmode':
      return (Icons.drive_eta_outlined, e.on ? tr('Mod mașină activ', 'Car mode on') : tr('Mod mașină oprit', 'Car mode off'));
    default:
      return (Icons.circle_outlined, '${e.t} ${e.d}');
  }
}

class DrivePage extends StatelessWidget {
  const DrivePage({super.key, required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final sb = SessionBuilder(prefix: app.prefix);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(fmtTime(s.startTime))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                Row(children: [OutcomeChip(s.outcome), const Spacer(), Text('${s.durationSec ~/ 60} min')]),
                const SizedBox(height: 10),
                KvTable([
                  (tr('Timp până la Android Auto', 'Time to Android Auto'), s.ttc == null ? '-' : '${s.ttc}s'),
                  (tr('Reîncercări', 'Retries'), '${s.retries}'),
                  if (s.cycles.isNotEmpty)
                    (tr('Încercări care au ajuns la Wi-Fi', 'Tries that reached Wi-Fi'),
                        s.dongleWifiSeen || s.cycles.any((c) => c.wifi) ? '${s.cycles.where((c) => c.wifi).length}/${s.cycles.length}' : tr('necunoscut', 'unknown')),
                  if (s.gaps.isNotEmpty) (tr('Pauze adaptor', 'Adapter gaps'), s.gaps.map((g) => '${g}s').join(', ')),
                  (tr('Întreruperi în mers', 'Drops while driving'), '${s.drops.length}'),
                  if (s.homeWifi != null) (tr('Wi-Fi acasă la pornire', 'Home Wi-Fi at start'), s.homeWifi!),
                  if (s.otherBt.isNotEmpty) (tr('Alte dispozitive BT', 'Other BT devices'), s.otherBt.join(', ')),
                  if (s.minRssi != null) (tr('Semnal minim adaptor', 'Min adapter signal'), '${s.minRssi} dBm'),
                  if (s.freq != null) (tr('Frecvență', 'Frequency'), '${s.freq} MHz'),
                  (tr('Baterie', 'Battery'), s.battery == null ? '-' : '${s.battery}%'),
                  (tr('Economizor / Doze', 'Saver / Doze'), '${s.saver ? tr('da', 'yes') : tr('nu', 'no')} / ${s.idle ? tr('da', 'yes') : tr('nu', 'no')}'),
                  ('Android Auto', s.aaVer ?? '-'),
                ]),
              ]),
            ),
          ),
          SectionTitle(tr('Cronologie', 'Timeline')),
          Card(
            child: Column(children: [
              for (final e in s.events)
                Builder(builder: (context) {
                  final (icon, text) = describe(e, sb);
                  final t = e.time;
                  return ListTile(
                    dense: true,
                    leading: Icon(icon, size: 20, color: cs.primary),
                    title: Text(text, style: const TextStyle(fontSize: 13.5)),
                    trailing: Text('${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
                  );
                }),
            ]),
          ),
        ],
      ),
    );
  }
}

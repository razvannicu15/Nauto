import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/native.dart';
import '../core/report.dart';
import 'widgets.dart';

class StatusPage extends StatelessWidget {
  const StatusPage({super.key, required this.onOpenDiagnosis});
  final VoidCallback onOpenDiagnosis;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = app.status;
    final running = app.running;
    final last = app.sessions.isEmpty ? null : app.sessions.first;
    final d = app.diagnosis;

    Future<void> later() async {
      await Future.delayed(const Duration(milliseconds: 1500));
      await app.refresh();
    }

    final checks = <_Check>[
      _Check(
        ok: s['permBt'] == true && s['permLoc'] == true && s['permNotif'] == true,
        title: tr('Permisiuni Bluetooth, locație, notificări', 'Bluetooth, location, notification permissions'),
        sub: tr('Ca să văd adaptorul și rețeaua Wi-Fi.', 'To see the adapter and the Wi-Fi network.'),
        action: () async {
          await Native.call('requestPerms');
          await later();
        },
      ),
      _Check(
        ok: s['permBgLoc'] == true,
        optional: true,
        title: tr('Locație „Permite tot timpul”', 'Location “Allow all the time”'),
        sub: tr('Opțional: numele rețelei Wi-Fi și în fundal.', 'Optional: Wi-Fi network name in the background too.'),
        action: () async {
          await Native.call('requestBgLocation');
          await later();
        },
      ),
      _Check(
        ok: s['selfOpt'] == false,
        title: tr('Nauto fără restricții de baterie', 'Nauto without battery restrictions'),
        sub: tr('Altfel Samsung poate opri monitorizarea.', 'Otherwise Samsung may stop monitoring.'),
        action: () => Native.call('ignoreBattery'),
      ),
      _Check(
        ok: s['aaOpt'] == false,
        title: tr('Android Auto fără restricții de baterie', 'Android Auto without battery restrictions'),
        sub: tr('Baterie → Nerestricționat.', 'Battery → Unrestricted.'),
        action: () => Native.call('openAa'),
      ),
      _Check(
        ok: app.phone.prefixBonded && ((s['bonded'] as List?)?.isNotEmpty ?? false),
        title: tr('Adaptorul ${app.prefix} e asociat', 'Adapter ${app.prefix} is paired'),
        sub: tr('Se caută după nume în Bluetooth.', 'Looked up by name in Bluetooth.'),
        action: () => Native.call('openBt'),
      ),
      _Check(
        ok: s['permLogs'] == true,
        optional: true,
        title: tr('Mod avansat (jurnale sistem)', 'Advanced mode (system logs)'),
        sub: tr('Opțional, din PC: Nauto.bat → [6].', 'Optional, from the PC: Nauto.bat → [6].'),
        action: null,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: (running ? Colors.green : cs.outline).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(running ? Icons.sensors : Icons.sensors_off,
                      color: running ? Colors.green : cs.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(running ? tr('Monitorizare activă', 'Monitoring on') : tr('Monitorizare oprită', 'Monitoring off'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                        running
                            ? tr('Rulează în fundal. Poți închide aplicația.', 'Runs in the background. You can close the app.')
                            : tr('Pornește și mergi normal cu mașina.', 'Turn it on and drive as usual.'),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ]),
                ),
                Switch(value: running, onChanged: (v) => app.setMonitoring(v)),
              ]),
              if (last != null) ...[
                const Divider(height: 28),
                Row(children: [
                  Expanded(
                    child: Text(tr('Ultimul drum: ${fmtTime(last.startTime)}', 'Last drive: ${fmtTime(last.startTime)}'),
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                  OutcomeChip(last.outcome),
                ]),
                if (last.ttc != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        tr('Android Auto a pornit în ${last.ttc}s · ${last.retries} reîncercări',
                            'Android Auto started in ${last.ttc}s · ${last.retries} retries'),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: running
                  ? () async {
                      await Native.call('mark');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(tr('Notat. Îl iau în calcul la diagnostic.', 'Noted. I\'ll use it in the diagnosis.'))));
                      }
                      await later();
                    }
                  : null,
              icon: const Icon(Icons.flag_outlined),
              label: Text(tr('Am avut o problemă acum', 'I just had a problem')),
            ),
          ),
        ]),
        if (d != null && d.total > 0) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              onTap: onOpenDiagnosis,
              leading: Icon(Icons.medical_services_outlined, color: cs.primary),
              title: Text(d.headline, style: const TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ],
        SectionTitle(tr('Configurare', 'Setup')),
        Card(
          child: Column(children: [
            for (final c in checks)
              ListTile(
                onTap: c.ok ? null : c.action,
                leading: Icon(
                  c.ok ? Icons.check_circle : (c.optional ? Icons.radio_button_unchecked : Icons.error_outline),
                  color: c.ok ? Colors.green : (c.optional ? cs.outline : cs.error),
                ),
                title: Text(c.title, style: const TextStyle(fontSize: 14.5)),
                subtitle: Text(c.sub, style: const TextStyle(fontSize: 12.5)),
                trailing: c.ok || c.action == null ? null : const Icon(Icons.chevron_right),
              ),
          ]),
        ),
        SectionTitle(tr('Telefon', 'Phone')),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: KvTable([
              (tr('Model', 'Model'), '${s['model'] ?? '-'}'),
              ('Android', '${s['android'] ?? '-'}'),
              ('Android Auto', '${s['aaVer'] ?? tr('neinstalat', 'not installed')}'),
              ('Bluetooth', s['btOn'] == true ? tr('pornit', 'on') : tr('oprit', 'off')),
              ('Wi-Fi', s['wifiOn'] == true ? tr('pornit', 'on') : tr('oprit', 'off')),
              (tr('Evenimente înregistrate', 'Recorded events'), '${app.events.length}'),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Check {
  _Check({required this.ok, required this.title, required this.sub, required this.action, this.optional = false});
  final bool ok, optional;
  final String title, sub;
  final VoidCallback? action;
}

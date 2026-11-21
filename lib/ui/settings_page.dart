import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import 'widgets.dart';

const buildNumber = String.fromEnvironment('BUILD', defaultValue: 'dev');
const builtAt = String.fromEnvironment('BUILT', defaultValue: '');

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _prefix = TextEditingController(text: app.prefix);

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('Setări', 'Settings'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SectionTitle(tr('Limbă', 'Language')),
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'ro', label: Text('Română')),
                const ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'system', label: Text(tr('Sistem', 'System'))),
              ],
              selected: {app.language},
              onSelectionChanged: (v) {
                app.language = v.first;
                app.save();
              },
            ),
            SectionTitle(tr('Temă', 'Theme')),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(tr('Sistem', 'System'))),
                ButtonSegment(value: ThemeMode.light, label: Text(tr('Luminoasă', 'Light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr('Întunecată', 'Dark'))),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (v) {
                app.themeMode = v.first;
                app.save();
              },
            ),
            SectionTitle(tr('Adaptor', 'Adapter')),
            TextField(
              controller: _prefix,
              decoration: InputDecoration(
                labelText: tr('Numele adaptorului în Bluetooth (început)', 'Adapter Bluetooth name (prefix)'),
                helperText: tr('Implicit AAWireless — se potrivește cu AAWireless-xxxx.', 'Default AAWireless — matches AAWireless-xxxx.'),
              ),
              onSubmitted: (v) {
                app.prefix = v.trim().isEmpty ? 'AAWireless' : v.trim();
                app.save();
                app.refresh();
              },
            ),
            SectionTitle(tr('Despre', 'About')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nauto', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                      tr('Diagnostic pentru Android Auto wireless. Fără reclame, fără cont, totul rămâne pe telefon.',
                          'Wireless Android Auto diagnostics. No ads, no account, everything stays on the phone.'),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  KvTable([
                    (tr('Versiune', 'Version'), '0.1.$buildNumber'),
                    if (builtAt.isNotEmpty) (tr('Compilat', 'Built'), builtAt),
                  ]),
                  const SizedBox(height: 8),
                  Text('by norAz', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

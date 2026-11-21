import 'package:flutter/material.dart';

import '../core/analyzer.dart';
import '../core/app_state.dart';
import '../core/i18n.dart';
import '../core/native.dart';
import '../core/report.dart';
import 'widgets.dart';

class DiagnosisPage extends StatelessWidget {
  const DiagnosisPage({super.key});

  Future<void> _export(BuildContext context) async {
    final d = app.diagnosis;
    if (d == null) return;
    final sys = app.filesDir.isEmpty ? <String>[] : await Native.sysLog(app.filesDir);
    final text = buildReport(status: app.status, d: d, sessions: app.sessions, events: app.events, sysLog: sys);
    final n = DateTime.now();
    final name = 'Nauto-${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}.txt';
    final path = await Native.save(name, text);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(path == null
          ? tr('Nu am putut salva raportul.', 'Could not save the report.')
          : tr('Salvat în $path — trimite-mi fișierul.', 'Saved to $path — send me the file.')),
    ));
  }

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Ștergi tot jurnalul?', 'Delete the whole journal?')),
        content: Text(tr('Diagnosticul o ia de la zero. Util după ce aplici o soluție.',
            'The diagnosis starts from zero. Useful after you apply a fix.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Renunță', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Șterge', 'Delete'))),
        ],
      ),
    );
    if (ok == true) {
      await Native.call('clear');
      await app.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = app.diagnosis;
    final cs = Theme.of(context).colorScheme;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final causes = d.findings.where((f) => f.kind == Kind.cause).toList();
    final checks = d.findings.where((f) => f.kind == Kind.check).toList();
    final progress = (d.total / Analyzer.goodDrives).clamp(0.0, 1.0).toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.headline, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Row(children: [
                StatBox('${d.total}', tr('drumuri', 'drives')),
                StatBox('${d.ok}', 'OK', color: Colors.green),
                StatBox('${d.bad}', tr('cu probleme', 'problems'), color: d.bad > 0 ? cs.error : null),
                StatBox(d.medianTtc == null ? '-' : '${d.medianTtc}s', tr('timp tipic', 'typical time')),
              ]),
              if (d.total < Analyzer.goodDrives) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 6),
                Text(
                    tr('${d.total}/${Analyzer.goodDrives} drumuri pentru un diagnostic sigur',
                        '${d.total}/${Analyzer.goodDrives} drives for a reliable diagnosis'),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
        if (causes.isNotEmpty) SectionTitle(tr('Cauze probabile', 'Likely causes')),
        for (final f in causes) ...[_FindingCard(f, provisional: !d.enough), const SizedBox(height: 8)],
        if (checks.isNotEmpty) SectionTitle(tr('De verificat pe telefon', 'Check on the phone')),
        for (final f in checks) ...[_FindingCard(f), const SizedBox(height: 8)],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => _export(context),
          icon: const Icon(Icons.ios_share),
          label: Text(tr('Exportă raportul complet', 'Export full report')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _clear(context),
          icon: const Icon(Icons.delete_outline),
          label: Text(tr('Șterge jurnalul', 'Clear journal')),
        ),
      ],
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard(this.f, {this.provisional = false});
  final Finding f;
  final bool provisional;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = f.kind == Kind.check ? cs.tertiary : (f.score >= 0.6 ? cs.error : cs.primary);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(f.kind == Kind.check ? Icons.tune : Icons.troubleshoot, color: color),
        title: Text(f.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: f.kind == Kind.cause
            ? Text(tr('Probabilitate: ${f.level}${provisional ? ' (provizoriu)' : ''}', 'Likelihood: ${f.level}${provisional ? ' (provisional)' : ''}'),
                style: TextStyle(fontSize: 12.5, color: color))
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.detail, style: const TextStyle(fontSize: 13.5, height: 1.35)),
          if (f.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(f.evidence, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Text(tr('Ce să faci', 'What to do'), style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
          const SizedBox(height: 6),
          for (var i = 0; i < f.fixes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: TextStyle(color: cs.onSurfaceVariant))),
                Expanded(child: Text(f.fixes[i], style: const TextStyle(fontSize: 13.5, height: 1.3))),
              ]),
            ),
        ],
      ),
    );
  }
}

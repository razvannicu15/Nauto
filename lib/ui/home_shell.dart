import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/i18n.dart';
import 'diagnosis_page.dart';
import 'drives_page.dart';
import 'settings_page.dart';
import 'status_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.startServices = true, this.initialTab = 0});

  /// False in tests: no platform channel.
  final bool startServices;
  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    if (!widget.startServices) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => app.refresh());
  }

  @override
  void dispose() {
    if (widget.startServices) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && widget.startServices) app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final titles = [tr('Stare', 'Status'), tr('Drumuri', 'Drives'), tr('Diagnostic', 'Diagnosis')];
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_tab == 0 ? 'Nauto' : titles[_tab]),
          actions: [
            IconButton(
              tooltip: tr('Reîmprospătează', 'Refresh'),
              onPressed: widget.startServices ? app.refresh : null,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: tr('Setări', 'Settings'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: widget.startServices ? app.refresh : () async {},
          child: switch (_tab) {
            0 => StatusPage(onOpenDiagnosis: () => setState(() => _tab = 2)),
            1 => const DrivesPage(),
            _ => const DiagnosisPage(),
          },
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.sensors_outlined), selectedIcon: const Icon(Icons.sensors), label: titles[0]),
            NavigationDestination(icon: const Icon(Icons.route_outlined), selectedIcon: const Icon(Icons.route), label: titles[1]),
            NavigationDestination(
                icon: const Icon(Icons.medical_services_outlined), selectedIcon: const Icon(Icons.medical_services), label: titles[2]),
          ],
        ),
      ),
    );
  }
}

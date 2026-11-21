import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nauto/main.dart';
import 'package:nauto/ui/home_shell.dart';

void main() {
  testWidgets('home renders all tabs without native services', (tester) async {
    await tester.pumpWidget(const NautoApp(home: HomeShell(startServices: false)));
    expect(find.text('Nauto'), findsWidgets);
    await tester.tap(find.byIcon(Icons.route_outlined));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.medical_services_outlined));
    await tester.pump();
  });
}

import 'package:aksab_admin/screens/tabs/managers_view.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Managers tab: unified names + monthly five-indicator targets.
// - top-level fullname, nested profile name, and missing name all render
//   (missing shows the explicit 'بدون اسم' badge, never a blank);
// - saving a monthly target writes targets.<yyyy-MM> with the five fields
//   plus audit data, without touching salary fields;
// - reopening the dialog shows the saved values (reviewable/editable).
void main() {
  Future<FakeFirebaseFirestore> seed() async {
    final fake = FakeFirebaseFirestore();
    await fake.collection('managers').doc('m1').set({
      'role': 'sales_manager',
      'fullname': 'مدير أول',
      'targetAmount': 10000,
    });
    await fake.collection('managers').doc('m2').set({
      'role': 'sales_manager',
      'profile': {'fullname': 'مدير ملف داخلي'},
    });
    await fake.collection('managers').doc('m3').set({
      'role': 'sales_manager',
      'phone': '01000000000',
    });
    await fake.collection('managers').doc('s1').set({
      'role': 'sales_supervisor',
      'fullname': 'مشرف',
      'managerId': 'm1',
    });
    return fake;
  }

  Future<void> pumpManagers(WidgetTester tester, FakeFirebaseFirestore fake) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ManagersView(firestore: fake))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows unified names incl. nested-profile and missing-name badge',
      (tester) async {
    final fake = await seed();
    await pumpManagers(tester, fake);

    expect(find.text('مدير أول'), findsOneWidget);
    expect(find.text('مدير ملف داخلي'), findsOneWidget);
    // Missing name is an explicit badge, never a blank card.
    expect(find.text('بدون اسم'), findsOneWidget);
    // Supervisor docs are not listed in the managers tab.
    expect(find.text('مشرف'), findsNothing);
  });

  testWidgets('saves five-indicator monthly target, salary fields untouched',
      (tester) async {
    final fake = await seed();
    await pumpManagers(tester, fake);

    // Open the target dialog for the first manager.
    await tester.tap(find.byIcon(Icons.track_changes).first);
    await tester.pumpAndSettle();

    // Month defaults to the current yyyy-MM.
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    expect(find.text(month), findsOneWidget);

    // Fill the five indicators.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(6)); // month + five indicators
    await tester.enterText(fields.at(1), '50000'); // financial
    await tester.enterText(fields.at(2), '160'); // hours
    await tester.enterText(fields.at(3), '120'); // invoices
    await tester.enterText(fields.at(4), '40'); // clients
    await tester.enterText(fields.at(5), '200'); // visits
    await tester.tap(find.text('حفظ الهدف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final snap = await fake.collection('managers').doc('m1').get();
    final data = snap.data()!;
    final entry = (data['targets'] as Map)[month] as Map;
    expect(entry['financialTarget'], 50000);
    expect(entry['hoursTarget'], 160);
    expect(entry['invoicesTarget'], 120);
    expect(entry['clientsTarget'], 40);
    expect(entry['visitsTarget'], 200);
    expect(entry['setByRole'], 'admin');
    expect((entry['history'] as List), hasLength(1));
    // Salary flow fields are preserved.
    expect(data['targetAmount'], 10000);
    expect(data.containsKey('lastSettledMonth'), isFalse);
  });

  testWidgets('reopening the dialog reviews saved values', (tester) async {
    final fake = await seed();
    await pumpManagers(tester, fake);

    await tester.tap(find.byIcon(Icons.track_changes).first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '7000');
    await tester.enterText(fields.at(5), '30');
    await tester.tap(find.text('حفظ الهدف'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.track_changes).first);
    await tester.pumpAndSettle();
    final reopened = find.byType(TextField);
    expect((reopened.at(1).evaluate().single.widget as TextField).controller?.text,
        '7000');
    expect((reopened.at(5).evaluate().single.widget as TextField).controller?.text,
        '30');
  });
}

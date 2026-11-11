import 'package:aksab_admin/screens/tabs/pending_view.dart';
import 'package:aksab_admin/screens/tabs/rep_type.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase-1: mandatory rep-type selection at approval time.
// The type is saved on the approved salesRep doc in the same write.
void main() {
  group('isRepTypeSelectionValid', () {
    test('sales_rep requires an explicit type', () {
      expect(
        isRepTypeSelectionValid(role: 'sales_rep', repType: null),
        isFalse,
      );
      expect(
        isRepTypeSelectionValid(role: 'sales_rep', repType: ''),
        isFalse,
      );
      expect(
        isRepTypeSelectionValid(role: 'sales_rep', repType: 'bogus'),
        isFalse,
      );
    });
    test('sales_rep accepts permanent or freelance', () {
      expect(
        isRepTypeSelectionValid(role: 'sales_rep', repType: 'permanent'),
        isTrue,
      );
      expect(
        isRepTypeSelectionValid(role: 'sales_rep', repType: 'freelance'),
        isTrue,
      );
    });
    test('other roles need no type', () {
      expect(
        isRepTypeSelectionValid(role: 'sales_manager', repType: null),
        isTrue,
      );
      expect(
        isRepTypeSelectionValid(role: 'sales_supervisor', repType: null),
        isTrue,
      );
    });
  });

  group('pending approval writes repType', () {
    Future<FakeFirebaseFirestore> seedRep() async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('pendingReps').doc('r1').set({
        'role': 'sales_rep',
        'fullname': 'مندوب اختبار',
        'email': 't@t.com',
        'phone': '01000000000',
      });
      return fake;
    }

    Future<void> pumpPending(WidgetTester tester, FakeFirebaseFirestore fake) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PendingView(firestore: fake))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('freelance approval stores repType on salesRep doc', (tester) async {
      final fake = await seedRep();
      await pumpPending(tester, fake);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Freelance — مندوب حر').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('اعتماد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final approved =
          await fake.collection('salesRep').doc('r1').get();
      expect(approved.exists, isTrue);
      expect(approved.data()?['repType'], 'freelance');
      expect(approved.data()?['status'], 'approved');
      expect(approved.data()?['repCode'], 'REP-r1');
      final pending =
          await fake.collection('pendingReps').doc('r1').get();
      expect(pending.exists, isFalse);
    });

    testWidgets('approval is blocked without a type selection', (tester) async {
      final fake = await seedRep();
      await pumpPending(tester, fake);

      await tester.tap(find.byIcon(Icons.check_circle));
      await tester.pump();
      await tester.tap(find.text('اعتماد'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Still pending: no salesRep doc, request untouched.
      final approved =
          await fake.collection('salesRep').doc('r1').get();
      expect(approved.exists, isFalse);
      final pending =
          await fake.collection('pendingReps').doc('r1').get();
      expect(pending.exists, isTrue);
      expect(find.text('اختر نوع المندوب أولاً (Permanent / Freelance)'),
          findsOneWidget);
    });
  });
}

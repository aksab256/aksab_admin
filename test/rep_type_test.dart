import 'package:aksab_admin/screens/tabs/rep_type.dart';
import 'package:aksab_admin/screens/tabs/supervisors_view.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// repType shared rules: missing/unknown counts as permanent; only explicit
// freelance is freelance. Supervisor linking must never show or touch
// freelance reps.
void main() {
  group('normalizeRepType', () {
    test('keeps explicit values, defaults the rest to permanent', () {
      expect(normalizeRepType('freelance'), 'freelance');
      expect(normalizeRepType('permanent'), 'permanent');
      expect(normalizeRepType(null), 'permanent');
      expect(normalizeRepType(''), 'permanent');
      expect(normalizeRepType('bogus'), 'permanent');
    });
  });

  group('isTargetEligible', () {
    test('only permanent (incl. legacy) reps enter targets', () {
      expect(isTargetEligible('permanent'), isTrue);
      expect(isTargetEligible(null), isTrue);
      expect(isTargetEligible('freelance'), isFalse);
    });
  });

  group('repTypeLabelAr', () {
    test('labels all three states', () {
      expect(repTypeLabelAr('permanent'), contains('ثابت'));
      expect(repTypeLabelAr('freelance'), contains('حر'));
      expect(repTypeLabelAr(null), contains('غير محدد'));
    });
  });

  group('supervisor linking excludes freelance', () {
    Future<FakeFirebaseFirestore> seed() async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('managers').doc('s1').set({
        'role': 'sales_supervisor',
        'fullname': 'مشرف',
      });
      await fake.collection('salesRep').doc('p1').set({
        'fullname': 'مندوب ثابت',
        'repCode': 'REP-p1',
        'repType': 'permanent',
      });
      await fake.collection('salesRep').doc('f1').set({
        'fullname': 'مندوب حر',
        'repCode': 'REP-f1',
        'repType': 'freelance',
      });
      await fake.collection('salesRep').doc('l1').set({
        'fullname': 'مندوب قديم',
        'repCode': 'REP-l1',
      });
      return fake;
    }

    testWidgets('dialog lists permanent+legacy only, save skips freelance',
        (tester) async {
      final fake = await seed();
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SupervisorsView(firestore: fake))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byIcon(Icons.handshake));
      await tester.pumpAndSettle();

      expect(find.text('مندوب ثابت'), findsOneWidget);
      expect(find.text('مندوب قديم'), findsOneWidget);
      expect(find.text('مندوب حر'), findsNothing);

      // Select the permanent rep and save.
      await tester.tap(find.text('مندوب ثابت'));
      await tester.pump();
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final perm = await fake.collection('salesRep').doc('p1').get();
      expect(perm.data()?['supervisorId'], 's1');
      final legacy = await fake.collection('salesRep').doc('l1').get();
      expect(legacy.data()?['supervisorId'], isNull);
      final free = await fake.collection('salesRep').doc('f1').get();
      expect(free.data()?['supervisorId'], isNull);
      expect(free.data(), isNot(contains('supervisorId')));
    });
  });
}

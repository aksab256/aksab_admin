import 'package:aksab_admin/screens/tabs/pending_staff_tab.dart';
import 'package:aksab_admin/widgets/seller_review_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Headless harness for the two admin reject controls. Each test seeds a
// fake pending doc, drives the real UI (reject -> confirm), and observes
// the pending-list removal outcome separately across pumped frames.
void main() {
  group('pending staff reject', () {
    testWidgets('confirming reject deletes the pending doc', (tester) async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('pendingReps').doc('01010000002').set({
        'fullname': 'Test Collector',
        'phone': '01010000002',
        'role': 'delivery_rep',
        'app': 'driver',
        'status': 'pending',
        'phoneVerified': false,
      });

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: PendingStaffTab(firestore: fake))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Real input: the pending request renders.
      expect(find.text('Test Collector'), findsOneWidget);

      // Real inputs: reject, then confirm the destructive dialog.
      await tester.tap(find.byIcon(Icons.cancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('حذف الطلب نهائيًا؟'), findsOneWidget);
      await tester.tap(find.text('حذف نهائي'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Outcome: the pending doc is gone and the list settles empty.
      final snap =
          await fake.collection('pendingReps').doc('01010000002').get();
      expect(snap.exists, isFalse);
      expect(find.text('Test Collector'), findsNothing);
      expect(find.text('لا توجد طلبات توظيف معلقة للتحصيل'), findsOneWidget);
    });
  });

  group('seller review reject', () {
    testWidgets('confirming reject deletes the pending seller',
        (tester) async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('pendingSellers').doc('201000000001').set({
        'fullname': 'Test Merchant',
        'phone': '201000000001',
        'merchantName': 'Test Store',
        'role': 'seller',
        'status': 'pending',
        'phoneVerified': false,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SellerReviewSheet(
            docId: '201000000001',
            data: const {
              'fullname': 'Test Merchant',
              'phone': '201000000001',
              'merchantName': 'Test Store',
              'role': 'seller',
            },
            firestore: fake,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Test Store'), findsOneWidget);

      // The sheet scrolls: bring the reject control into view first.
      await tester.ensureVisible(find.text('رفض الطلب وحذفه نهائيًا'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رفض الطلب وحذفه نهائيًا'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('حذف طلب التاجر نهائيًا؟'), findsOneWidget);
      await tester.tap(find.text('حذف نهائي'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Outcome: the pending seller doc is gone.
      final snap = await fake
          .collection('pendingSellers')
          .doc('201000000001')
          .get();
      expect(snap.exists, isFalse);
    });
  });
}

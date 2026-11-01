import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PendingStaffTab extends StatelessWidget {
  final FirebaseFirestore? firestore;
  const PendingStaffTab({super.key, this.firestore});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot>>(
      stream: _getCombinedPendingStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("خطأ في الاتصال"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text("لا توجد طلبات توظيف معلقة للتحصيل", style: TextStyle(fontFamily: 'Cairo')));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data![index];
            var data = doc.data() as Map<String, dynamic>;
            // نتحقق إذا كان المستند من مجموعة المديرين
            bool isManager = doc.reference.path.contains('pendingManagers');

            return _buildStaffRequestCard(context, doc.id, data, isManager);
          },
        );
      },
    );
  }

  // الدالة المحدثة بفلترة الأدوار
  Stream<List<QueryDocumentSnapshot>> _getCombinedPendingStream() {
    return (firestore ?? FirebaseFirestore.instance)
        .collection('pendingReps')
        .where('role', isEqualTo: 'delivery_rep') // جلب مناديب التحصيل فقط وتجاهل sales_rep
        .snapshots()
        .map((repsSnap) => repsSnap.docs)
        .asyncMap((repsDocs) async {
          // جلب المديرين والمشرفين المعلقين بشرط أن يكونوا تابعين لقسم التحصيل
          var mgrsSnap = await (firestore ?? FirebaseFirestore.instance)
              .collection('pendingManagers')
              .where('role', whereIn: ['delivery_manager', 'delivery_supervisor'])
              .get();
          
          // دمج النتائج المفلترة
          return [...repsDocs, ...mgrsSnap.docs];
        });
  }

  Widget _buildStaffRequestCard(BuildContext context, String uid, Map<String, dynamic> data, bool isManager) {
    // تحديد المسمى الوظيفي بناءً على الدور الفعلي المخزن
    String roleLabel = "موظف";
    if (data['role'] == 'delivery_manager') roleLabel = "مدير تحصيل";
    if (data['role'] == 'delivery_supervisor') roleLabel = "مشرف تحصيل";
    if (data['role'] == 'delivery_rep') roleLabel = "مندوب تحصيل شركة";

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isManager ? Colors.green.shade100 : Colors.orange.shade100,
          child: Icon(
            isManager ? Icons.admin_panel_settings : Icons.badge,
            color: isManager ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(data['fullname'] ?? '', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        subtitle: Text("$roleLabel | ${data['phone']}", style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.cancel, color: Colors.red),
              tooltip: 'رفض وحذف الطلب',
              onPressed: () => _rejectStaff(context, uid, isManager),
            ),
            ElevatedButton(
              onPressed: () => _openActivationDialog(context, uid, data, isManager),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A2C3D)),
              child: const Text("تفعيل", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rejectStaff(BuildContext context, String uid, bool isManager) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الطلب نهائيًا؟', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        content: const Text('سيُحذف الطلب من قائمة الانتظار كأن لم يكن، ولن يُرسل أي رمز.',
            textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final sourceCol = isManager ? 'pendingManagers' : 'pendingReps';
      await (firestore ?? FirebaseFirestore.instance).collection(sourceCol).doc(uid).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الطلب نهائيًا', style: TextStyle(fontFamily: 'Cairo'))),
        );
      }
    } catch (e) {
      debugPrint('reject staff failed: $e');
    }
  }

  void _openActivationDialog(BuildContext context, String uid, Map<String, dynamic> data, bool isManager) {
    // توليد الكود تلقائياً بناءً على الدور
    String prefix = (data['role'] == 'delivery_rep') ? "REP-" : "MGR-";
    final TextEditingController codeController = TextEditingController(text: "$prefix${data['phone']}");
    final TextEditingController salaryController = TextEditingController(text: "4000");
    final TextEditingController commController = TextEditingController(text: "0");
    final TextEditingController supIdController = TextEditingController(text: "91nXwJXt3LzH09Ox46La");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تفعيل واعتماد بيانات الموظف", textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeController, decoration: const InputDecoration(labelText: "كود التعريف (Code)")),
              Row(
                children: [
                  Expanded(child: TextField(controller: salaryController, decoration: const InputDecoration(labelText: "الراتب"), keyboardType: TextInputType.number)),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: commController, decoration: const InputDecoration(labelText: "العمولة %"), keyboardType: TextInputType.number)),
                ],
              ),
              // المندوب فقط يحتاج لتحديد مشرف
              if (data['role'] == 'delivery_rep') 
                TextField(controller: supIdController, decoration: const InputDecoration(labelText: "معرف المشرف المسؤول")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
          ElevatedButton(
            onPressed: () => _executeActivation(context, uid, data, isManager, {
              'code': codeController.text,
              'salary': double.tryParse(salaryController.text) ?? 0,
              'comm': double.tryParse(commController.text) ?? 0,
              'supId': supIdController.text,
            }),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("تأكيد التفعيل", style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _executeActivation(BuildContext context, String uid, Map<String, dynamic> data, bool isManager, Map<String, dynamic> inputs) async {
    try {
      // تحديد المجموعات بناءً على الدور
      String targetCol = (data['role'] == 'delivery_rep') ? "deliveryReps" : "managers";
      String sourceCol = isManager ? "pendingManagers" : "pendingReps";

      final payload = {
        ...data,
        'repCode': inputs['code'],
        'baseSalary': inputs['salary'],
        'commissionRate': inputs['comm'],
        'status': "approved",
        'approvedAt': FieldValue.serverTimestamp(),
        'uid': uid,
      };

      if (data['role'] == 'delivery_rep') {
        payload['supervisorId'] = inputs['supId'];
        payload['walletBalance'] = 0;
      }

      await (firestore ?? FirebaseFirestore.instance).collection(targetCol).doc(uid).set(payload);
      await (firestore ?? FirebaseFirestore.instance).collection(sourceCol).doc(uid).delete();

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("تم بنجاح نقل ${data['fullname']} إلى مجموعة $targetCol"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }
}


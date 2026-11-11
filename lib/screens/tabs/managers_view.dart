import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../salary_detail_screen.dart'; // استيراد شاشة الرواتب المعتمدة
import 'manager_targets.dart';
import 'staff_display_name.dart';

class ManagersView extends StatelessWidget {
  final FirebaseFirestore? firestore;
  const ManagersView({super.key, this.firestore});

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
    // الشهر الحالي بصيغة موحدة yyyy-MM (نفس الصيغة في كل مواضع الأهداف).
    final String currentMonth = managerMonthKey(DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('managers')
          .where('role', isEqualTo: 'sales_manager')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;

        if (docs.isEmpty) return const Center(child: Text("لا يوجد مديرو مبيعات حالياً"));

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var manager = docs[index].data() as Map<String, dynamic>;
            var managerId = docs[index].id;

            // التحقق هل تم اعتماد راتب هذا الشهر؟
            bool isSettled = manager['lastSettledMonth'] == currentMonth;
            final summary = summarizeManagerMonth(manager['targets'], currentMonth);
            final bool hasTarget = summary['hasTarget'] as bool;
            final values = summary['values'] as Map<String, double>;

            return Card(
              elevation: 3,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Stack(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF1A2C3D),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    // نقطة التنبيه إذا لم يتم الاعتماد
                    if (!isSettled)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                        ),
                      ),
                  ],
                ),
                title: InkWell(
                  onTap: () => _navigateToSalary(context, managerId, 'manager'),
                  child: Text(
                    staffDisplayName(manager),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // مستهدف الراتب الشهري — حقل salary منفصل تمامًا عن هدف المبيعات.
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text("مستهدف الراتب الشهري: ${manager['targetAmount'] ?? 0}",
                            style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Cairo')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // هدف المبيعات الشهري (المؤشرات الخمسة) — قراءة فقط هنا.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasTarget ? Colors.teal[50] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        hasTarget
                            ? "هدف مبيعات $currentMonth: مالي ${values['financialTarget']!.toStringAsFixed(0)} | "
                                "فواتير ${values['invoicesTarget']!.toStringAsFixed(0)} | "
                                "عملاء ${values['clientsTarget']!.toStringAsFixed(0)} | "
                                "زيارات ${values['visitsTarget']!.toStringAsFixed(0)} | "
                                "ساعات ${values['hoursTarget']!.toStringAsFixed(0)}"
                            : "لم يُحدد هدف $currentMonth بعد",
                        style: TextStyle(
                          fontSize: 10,
                          color: hasTarget ? Colors.teal[900] : Colors.grey[700],
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    // الليبل التوضيحي
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSettled ? Colors.green[100] : Colors.orange[100],
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isSettled ? "تم اعتماد الراتب ✅" : "بإنتظار الاعتماد ⏳",
                        style: TextStyle(
                          fontSize: 10,
                          color: isSettled ? Colors.green[800] : Colors.orange[900],
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                  ],
                ),
                // زر الهدف الشهري + زر التعيين (الموجود سابقاً)
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.track_changes,
                        color: hasTarget ? Colors.teal : Colors.grey,
                      ),
                      tooltip: hasTarget ? "مراجعة / تعديل الهدف" : "تسجيل الهدف الشهري",
                      onPressed: () => _showManagerTargetDialog(context, db, managerId, manager),
                    ),
                    IconButton(
                      icon: const Icon(Icons.group_add, color: Colors.orange),
                      onPressed: () => _showAssignmentDialog(
                          context, db, managerId, staffDisplayName(manager)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // دالة الانتقال لشاشة الرواتب
  void _navigateToSalary(BuildContext context, String id, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalaryDetailScreen(
          employeeId: id,
          employeeType: type,
        ),
      ),
    );
  }

  /// حوار تسجيل / مراجعة الهدف الشهري للمدير (المؤشرات الخمسة).
  ///
  /// الكتابة دمج يدوي لخريطة `targets` كاملة بعد قراءة حديثة للمستند، مع
  /// إلحاق سجل تدقيق. لا يُستخدم `locked: true` هنا عمداً: هدف المدير
  /// يُستكمل على مراحل (استلام ثم توزيع لاحقاً)، والقفل سيمنع ذلك.
  void _showManagerTargetDialog(BuildContext context, FirebaseFirestore db,
      String managerId, Map<String, dynamic> managerData) {
    final String name = staffDisplayName(managerData);
    final String defaultMonth = managerMonthKey(DateTime.now());
    final existing = summarizeManagerMonth(managerData['targets'], defaultMonth);
    final Map<String, double> current =
        Map<String, double>.from(existing['values'] as Map);

    String fmt(double v) => v == 0 ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    final monthCtrl = TextEditingController(text: defaultMonth);
    final ctrls = <String, TextEditingController>{
      for (final field in kManagerTargetFields)
        field: TextEditingController(text: fmt(current[field] ?? 0)),
    };
    // Kept outside the StatefulBuilder: the builder re-runs on every
    // setDialogState, which would reset an error declared inside it.
    String? error;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text("الهدف الشهري: $name",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: monthCtrl,
                    decoration: const InputDecoration(
                      labelText: "الشهر (yyyy-MM)",
                      prefixIcon: Icon(Icons.calendar_month),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final field in kManagerTargetFields) ...[
                    TextField(
                      controller: ctrls[field],
                      decoration: InputDecoration(
                        labelText: kManagerTargetLabelsAr[field],
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12, fontFamily: 'Cairo')),
                  const Text(
                    "يُحفظ داخل targets.<الشهر> مع من سجّله ووقته وسجل تعديلات. التوزيع على المشرفين مرحلة لاحقة.",
                    style: TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () async {
                  final month = monthCtrl.text.trim();
                  if (!isValidManagerMonthKey(month)) {
                    setDialogState(() => error = "صيغة الشهر غير صالحة (مثال: $defaultMonth)");
                    return;
                  }
                  final raw = {for (final e in ctrls.entries) e.key: e.value.text};
                  final validationError = validateManagerTargets(raw);
                  if (validationError != null) {
                    setDialogState(() => error = validationError);
                    return;
                  }
                  String uid = 'admin-panel';
                  try {
                    uid = FirebaseAuth.instance.currentUser?.uid ?? 'admin-panel';
                  } catch (_) {
                    uid = 'admin-panel';
                  }
                  try {
                    final snap = await db.collection('managers').doc(managerId).get();
                    final fresh = snap.data() ?? <String, dynamic>{};
                    final allTargets = (fresh['targets'] is Map)
                        ? Map<String, dynamic>.from(fresh['targets'] as Map)
                        : <String, dynamic>{};
                    final prevEntry = allTargets[month];
                    final prevHistory = (prevEntry is Map && prevEntry['history'] is List)
                        ? (prevEntry['history'] as List)
                        : null;
                    allTargets[month] = buildManagerTargetEntry(
                      values: raw,
                      setByUid: uid,
                      setByRole: 'admin',
                      now: DateTime.now(),
                      previousHistory: prevHistory,
                    );
                    await db.collection('managers').doc(managerId).update({'targets': allTargets});
                  } catch (e) {
                    if (dialogContext.mounted) {
                      setDialogState(() => error = "تعذّر الحفظ: $e");
                    }
                    return;
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text("حفظ الهدف", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ... دالة _showAssignmentDialog تبقى كما هي بدون تغيير ...
  void _showAssignmentDialog(BuildContext context, FirebaseFirestore db, String managerId, String name) async {
    var allSups = await db.collection('managers').where('role', isEqualTo: 'sales_supervisor').get();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        List<String> selectedIds = [];
        for (var doc in allSups.docs) {
          final data = doc.data();
          if (data['managerId'] == managerId) selectedIds.add(doc.id);
        }
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text("تعيين مشرفين لـ $name", style: const TextStyle(fontFamily: 'Cairo')),
            content: SizedBox(
              width: double.maxFinite,
              child: allSups.docs.isEmpty
                  ? const Text("لا يوجد مشرفون متاحون حالياً")
                  : ListView(
                      shrinkWrap: true,
                      children: allSups.docs.map((doc) {
                        final data = doc.data();
                        return CheckboxListTile(
                          title: Text(staffDisplayName(data)),
                          value: selectedIds.contains(doc.id),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                selectedIds.add(doc.id);
                              } else {
                                selectedIds.remove(doc.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
              ElevatedButton(
                onPressed: () async {
                  WriteBatch batch = db.batch();
                  for (var doc in allSups.docs) {
                    batch.update(doc.reference, {'managerId': selectedIds.contains(doc.id) ? managerId : null});
                  }
                  await batch.commit();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("حفظ التغييرات"),
              )
            ],
          ),
        );
      },
    );
  }
}

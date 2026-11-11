import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../salary_detail_screen.dart'; // الشاشة الجديدة التي صممناها
import 'staff_display_name.dart';
import 'rep_type.dart';

class RepsView extends StatelessWidget {
  const RepsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      // مراقبة كولكشن المناديب بشكل لحظي
      stream: FirebaseFirestore.instance.collection('salesRep').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text("لا يوجد مناديب مبيعات حالياً", style: TextStyle(fontFamily: 'Cairo')),
          );
        }

        var docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var rep = docs[index].data() as Map<String, dynamic>;
            var repId = docs[index].id;

            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1A2C3D),
                  child: Icon(Icons.badge, color: Colors.white),
                ),
                title: InkWell(
                  onTap: () => _navigateToSalary(context, repId, staffDisplayName(rep)),
                  child: Text(
                    staffDisplayName(rep),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      fontFamily: 'Cairo'
                    ),
                  ),
                ),
                subtitle: Text("كود المندوب: ${rep['repCode'] ?? 'غير معرف'}\nالنوع: ${repTypeLabelAr(rep['repType'])}"),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _navigateToSalary(context, repId, staffDisplayName(rep)),
              ),
            );
          },
        );
      },
    );
  }

  void _navigateToSalary(BuildContext context, String id, String name) {
    // الانتقال هنا آمن تماماً ولا يسبب تجمد التطبيق
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SalaryDetailScreen(
          employeeId: id,
          employeeType: 'rep', // تحديد النوع لضمان جلب البيانات الصحيحة
        ),
      ),
    );
  }
}


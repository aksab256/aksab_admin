import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'staff_display_name.dart';

class ManagersTab extends StatelessWidget {
  const ManagersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('managers').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text("خطأ في البيانات"));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            return _buildManagerCard(context, doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildManagerCard(BuildContext context, String uid, Map<String, dynamic> data) {
    bool isSupervisor = data['role'] == 'delivery_supervisor';
    String roleName = isSupervisor ? "مشرف تحصيل" : "مدير تحصيل";

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSupervisor ? Colors.blue.shade800 : Colors.black87,
          child: Icon(isSupervisor ? Icons.support_agent : Icons.admin_panel_settings, color: Colors.white),
        ),
        title: Text(staffDisplayName(data), style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        subtitle: Text("$roleName | كود: ${data['repCode'] ?? '---'}", style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.settings, color: Color(0xFF1A2C3D)),
          onPressed: () => _showEditManagerDialog(context, uid, data),
        ),
      ),
    );
  }

  void _showEditManagerDialog(BuildContext context, String uid, Map<String, dynamic> data) {
    final salaryCont = TextEditingController(text: data['baseSalary']?.toString() ?? "0");
    String? selectedManagerId = data['managerId']; // الحقل الذي يربط المشرف بمديره
    bool isSupervisor = data['role'] == 'delivery_supervisor';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("تعديل بيانات ${isSupervisor ? 'المشرف' : 'المدير'}", textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: salaryCont, decoration: const InputDecoration(labelText: "الراتب الأساسي"), keyboardType: TextInputType.number),
              
              // إذا كان الشخص "مشرفاً"، نعرض له قائمة "المديرين" ليتبع أحدهم
              if (isSupervisor) ...[
                const SizedBox(height: 20),
                const Text("المدير المسؤول عن هذا المشرف:", style: TextStyle(fontSize: 12, fontFamily: 'Cairo')),
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance.collection('managers').where('role', isEqualTo: 'delivery_manager').get(),
                  builder: (context, mgrSnap) {
                    if (!mgrSnap.hasData) return const LinearProgressIndicator();
                    return DropdownButton<String>(
                      isExpanded: true,
                      value: selectedManagerId,
                      items: mgrSnap.data!.docs.map((mDoc) => DropdownMenuItem(

                        value: mDoc.id,
                        child: Text(staffDisplayName(mDoc.data() as Map<String, dynamic>), style: const TextStyle(fontSize: 14)),
                      )).toList(),
                      onChanged: (val) => setDialogState(() => selectedManagerId = val),
                    );
                  },
                ),
              ]
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
            ElevatedButton(
              onPressed: () async {
                Map<String, dynamic> updates = {'baseSalary': double.tryParse(salaryCont.text) ?? 0};
                if (isSupervisor) updates['managerId'] = selectedManagerId;
                
                await FirebaseFirestore.instance.collection('managers').doc(uid).update(updates);
                Navigator.pop(ctx);
              },
              child: const Text("حفظ"),
            )
          ],
        ),
      ),
    );
  }
}


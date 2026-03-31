import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🚀 المحرك المعتمد الجديد
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

class RetailerBannersTab extends StatefulWidget {
  const RetailerBannersTab({super.key});

  @override
  State<RetailerBannersTab> createState() => _RetailerBannersTabState();
}

class _RetailerBannersTabState extends State<RetailerBannersTab> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orderController = TextEditingController(text: "0");

  String _linkType = 'NONE';
  String? _targetId;
  XFile? _selectedImage;
  bool _isUploading = false;

  // 🎯 الطريقة المعتمدة للرفع (Firebase Storage + Bytes) بدلاً من Cloudinary
  Future<Map<String, String>?> _uploadToFirebase() async {
    if (_selectedImage == null) return null;
    try {
      String fileName = 'banners/retailer/${DateTime.now().millisecondsSinceEpoch}_banner.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // قراءة الملف كـ Bytes لضمان التوافق التام (ويب + موبايل)
      final bytes = await _selectedImage!.readAsBytes();
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

      // الرفع المباشر
      UploadTask uploadTask = storageRef.putData(bytes, metadata);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return {
        'url': downloadUrl,
        'public_id': fileName
      };
    } catch (e) {
      debugPrint("Firebase Storage Error: $e");
      return null;
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى ملء البيانات واختيار صورة")));
      return;
    }

    setState(() => _isUploading = true);
    try {
      // استخدام المحرك الجديد
      final uploadResult = await _uploadToFirebase();
      
      if (uploadResult != null) {
        // الحفاظ على نفس الحقول القديمة بالنص لضمان عمل تطبيق المشتري
        await FirebaseFirestore.instance.collection('retailerBanners').add({
          'name': _nameController.text.trim(),
          'imageUrl': uploadResult['url'],
          'imagePublicId': uploadResult['public_id'], // أضفناه للأمان والحذف لاحقاً
          'order': int.tryParse(_orderController.text) ?? 0,
          'linkType': _linkType,
          'targetId': _targetId ?? '',
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });

        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم رفع البانر الذكي بنجاح!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحفظ: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _resetForm() {
    _nameController.clear();
    _orderController.text = "0";
    setState(() {
      _selectedImage = null;
      _linkType = 'NONE';
      _targetId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildFormCard(),
          const SizedBox(height: 25),
          const Divider(),
          const Text("البانرات الحالية لتاجر التجزئة",
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 15),
          _buildBannersList(),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("إعداد الوجهة الذكية",
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
              const SizedBox(height: 15),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "اسم البانر (للوصف)", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "مطلوب" : null,
              ),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _linkType,
                decoration: const InputDecoration(labelText: "نوع الوجهة (أين يذهب المستخدم؟)", border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'NONE', child: Text("بدون وجهة (صورة فقط)")),
                  DropdownMenuItem(value: 'CATEGORY', child: Text("فتح قسم رئيسي (Main Category)")),
                  DropdownMenuItem(value: 'SUB_CATEGORY', child: Text("فتح قسم فرعي (عرض منتجات)")),
                  DropdownMenuItem(value: 'RETAILER', child: Text("فتح صفحة تاجر (Seller)")),
                ],
                onChanged: (v) => setState(() {
                  _linkType = v!;
                  _targetId = null;
                }),
              ),
              if (_linkType != 'NONE') ...[
                const SizedBox(height: 15),
                _buildTargetDropdown(),
              ],
              const SizedBox(height: 15),
              _buildImagePicker(),
              const SizedBox(height: 15),
              TextFormField(
                controller: _orderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "ترتيب الظهور", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("حفظ ورفع البانر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetDropdown() {
    String collection;
    if (_linkType == 'CATEGORY') {
      collection = 'mainCategory';
    } else if (_linkType == 'SUB_CATEGORY') {
      collection = 'subCategory';
    } else {
      collection = 'sellers';
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        if (snapshot.data!.docs.isEmpty) return const Text("القائمة فارغة في قاعدة البيانات");

        return DropdownButtonFormField<String>(
          value: _targetId,
          hint: const Text("اختر الوجهة المحددة"),
          decoration: const InputDecoration(border: OutlineInputBorder(), fillColor: Color(0xFFF0F7FF), filled: true),
          items: snapshot.data!.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String displayText = "";
            if (_linkType == 'RETAILER') {
              String mName = data['merchantName'] ?? 'بدون اسم تجاري';
              String phone = data['additionalPhone'] ?? '';
              displayText = phone.isNotEmpty ? "$mName ($phone)" : mName;
            } else {
              displayText = data['name'] ?? 'بدون اسم';
            }
            return DropdownMenuItem(value: doc.id, child: Text(displayText));
          }).toList(),
          onChanged: (v) => setState(() => _targetId = v),
          validator: (v) => v == null ? "يجب اختيار وجهة" : null,
        );
      },
    );
  }

  Widget _buildImagePicker() {
    return InkWell(
      onTap: () async {
        final img = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (img != null) setState(() => _selectedImage = img);
      },
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade200),
          borderRadius: BorderRadius.circular(12),
          color: Colors.blue.shade50,
        ),
        child: _selectedImage == null
            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_a_photo, size: 40, color: Colors.blue),
                Text("اختر صورة البانر")
              ])
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: kIsWeb
                    ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                    : Image.file(io.File(_selectedImage!.path), fit: BoxFit.cover)),
      ),
    );
  }

  Widget _buildBannersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('retailerBanners').orderBy('order').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Image.network(data['imageUrl'], width: 50, height: 50, fit: BoxFit.cover),
                title: Text(data['name'] ?? ''),
                subtitle: Text("النوع: ${data['linkType']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  onPressed: () async {
                    // حذف الوثيقة والصورة من الاستورج
                    await FirebaseFirestore.instance.collection('retailerBanners').doc(doc.id).delete();
                    if (data['imagePublicId'] != null) {
                      try {
                        await FirebaseStorage.instance.ref().child(data['imagePublicId']).delete();
                      } catch (e) {
                        debugPrint("Delete error: $e");
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}


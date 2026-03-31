// المسار: lib/screens/marketing/tabs/consumer_banners_tab.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🚀 المحرك المعتمد الجديد
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

class ConsumerBannersTab extends StatefulWidget {
  const ConsumerBannersTab({super.key});

  @override
  State<ConsumerBannersTab> createState() => _ConsumerBannersTabState();
}

class _ConsumerBannersTabState extends State<ConsumerBannersTab> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orderController = TextEditingController(text: "0");

  String _targetAudience = 'general';
  String? _selectedOwnerId;
  String _linkType = 'NONE';
  String? _targetId;
  XFile? _selectedImage;
  bool _isUploading = false;

  // 🎯 الطريقة المعتمدة للرفع (Firebase Storage + Bytes)
  Future<Map<String, String>?> _uploadToFirebase() async {
    if (_selectedImage == null) return null;
    try {
      String fileName = 'banners/consumer/${DateTime.now().millisecondsSinceEpoch}_banner.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      final bytes = await _selectedImage!.readAsBytes();
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("برجاء إكمال البيانات وصورة البانر")));
      return;
    }
    setState(() => _isUploading = true);
    try {
      final uploadResult = await _uploadToFirebase();
      
      if (uploadResult != null) {
        // 🎯 الحفاظ على نفس أسماء الحقول بالنص لضمان عمل تطبيق المستهلك
        await FirebaseFirestore.instance.collection('consumerBanners').add({
          'name': _nameController.text.trim(),
          'imageUrl': uploadResult['url'],
          'imagePublicId': uploadResult['public_id'], // للحذف لاحقاً
          'linkType': _linkType,
          'targetId': _targetId ?? '',
          'targetAudience': _targetAudience,
          'ownerId': _targetAudience == 'dealer' ? _selectedOwnerId : '',
          'order': int.tryParse(_orderController.text) ?? 0,
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
        _resetForm();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم رفع البانر بنجاح!")));
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
      _targetAudience = 'general';
      _selectedOwnerId = null;
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
          const Text("البانرات الحالية للمستهلك", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 15),
          _buildBannersList(),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("إضافة بانر جديد", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "اسم البانر داخلياً", border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? "مطلوب" : null,
              ),
              const SizedBox(height: 15),
              _buildImagePicker(),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: _linkType,
                decoration: const InputDecoration(labelText: "نوع الوجهة (أين يفتح؟)", border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'NONE', child: Text("بدون وجهة (صورة فقط)")),
                  DropdownMenuItem(value: 'CATEGORY', child: Text("فتح قسم رئيسي")),
                  DropdownMenuItem(value: 'SUB_CATEGORY', child: Text("فتح قسم فرعي")),
                  DropdownMenuItem(value: 'RETAILER', child: Text("سوبر ماركت (توصيل)")),
                  DropdownMenuItem(value: 'SELLER', child: Text("تاجر (ملابس/أخرى)")),
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
              const SizedBox(height: 20),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("حفظ البانر", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    String nameField = 'name';

    switch (_linkType) {
      case 'CATEGORY':
        collection = 'mainCategory';
        break;
      case 'SUB_CATEGORY':
        collection = 'subCategory';
        break;
      case 'RETAILER':
        collection = 'deliverySupermarkets';
        nameField = 'supermarketName';
        break;
      case 'SELLER':
        collection = 'sellers';
        nameField = 'merchantName';
        break;
      default:
        return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        var docs = snapshot.data!.docs;
        if (docs.isEmpty) return Text("لا توجد بيانات في $collection");

        return DropdownButtonFormField<String>(
          value: _targetId,
          hint: const Text("اختر الوجهة المحددة"),
          decoration: const InputDecoration(border: OutlineInputBorder(), filled: true, fillColor: Color(0xFFF0F7FF)),
          items: docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem(
              value: doc.id,
              child: Text(data[nameField] ?? 'بدون اسم (${doc.id})'),
            );
          }).toList(),
          onChanged: (v) => setState(() => _targetId = v),
          validator: (v) => v == null ? "مطلوب" : null,
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
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[50]),
        child: _selectedImage == null
            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                Text("اختر صورة البانر")
              ])
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: kIsWeb
                    ? Image.network(_selectedImage!.path, fit: BoxFit.contain)
                    : Image.file(io.File(_selectedImage!.path), fit: BoxFit.contain)),
      ),
    );
  }

  Widget _buildBannersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('consumerBanners').orderBy('order').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
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
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(data['imageUrl'], width: 60, height: 60, fit: BoxFit.cover),
                ),
                title: Text(data['name'] ?? 'بدون اسم'),
                subtitle: Text("الوجهة: ${data['linkType']}"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteBanner(doc.id, data['imagePublicId']),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _deleteBanner(String id, String? storagePath) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف البانر؟"),
        content: const Text("هل أنت متأكد من حذف هذا البانر نهائياً؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("إلغاء")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("حذف", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance.collection('consumerBanners').doc(id).delete();
      if (storagePath != null) {
        try {
          await FirebaseStorage.instance.ref().child(storagePath).delete();
        } catch (e) {
          debugPrint("Delete error: $e");
        }
      }
    }
  }
}


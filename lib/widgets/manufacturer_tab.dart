// المسار: lib/widgets/manufacturer_tab.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // الانتقال للمحرك الموحد
import 'dart:io' as io;

class ManufacturerTab extends StatefulWidget {
  const ManufacturerTab({super.key});

  @override
  State<ManufacturerTab> createState() => _ManufacturerTabState();
}

class _ManufacturerTabState extends State<ManufacturerTab> {
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  XFile? _selectedImage;
  bool _isLoading = false;

  // قائمة لتخزين معرفات الأقسام المختارة (لربط الشركة بأقسامها)
  List<String> _selectedSubCategoryIds = [];

  // --- 1. التقاط الشعار (Logo) ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedImage = image);
  }

  // --- 2. محرك الرفع الموحد (نفس خلطة الأقسام والمنتجات) ---
  Future<Map<String, String>?> _uploadToFirebase(XFile xFile) async {
    try {
      String fileName = 'manufacturers/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // قراءة الملف كـ Bytes لضمان التوافق التام
      final bytes = await xFile.readAsBytes();
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

      // استخدام putData (الخيار الأضمن للويب والموبايل)
      UploadTask uploadTask = storageRef.putData(bytes, metadata);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return {
        'url': downloadUrl,
        'public_id': fileName
      };
    } catch (e) {
      debugPrint("❌ Firebase Storage Upload Error: $e");
      return null;
    }
  }

  // --- 3. حفظ الشركة (مع الحفاظ على الحقول بدقة) ---
  Future<void> _saveManufacturer() async {
    if (_nameController.text.isEmpty || _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("برجاء إدخال الاسم واختيار الصورة")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uploadResult = await _uploadToFirebase(_selectedImage!);
      
      if (uploadResult != null) {
        // 🎯 الحفاظ على أسماء الحقول لتطابق الموديل في الفرونت (المشتري والمناديب)
        await FirebaseFirestore.instance.collection('manufacturers').add({
          'name': _nameController.text.trim(),
          'imageUrl': uploadResult['url'], // الحقل المسؤول عن عرض الصورة
          'imagePublicId': uploadResult['public_id'],
          'isActive': true,
          'subCategoryIds': _selectedSubCategoryIds,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        _resetForm();
        _showSuccessSnackBar("تم إضافة الشركة بنجاح بنظام بلازا الموحد");
      } else {
        throw Exception("فشل رفع شعار الشركة");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetForm() {
    _nameController.clear();
    setState(() {
      _selectedImage = null;
      _selectedSubCategoryIds = [];
    });
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  // --- 4. واجهة المستخدم (UI) ---
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNameInput(),
            const SizedBox(height: 20),
            const Text("اختر الأقسام الفرعية المرتبطة بالشركة:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildSubCategorySelector(),
            const SizedBox(height: 20),
            _buildLogoPicker(),
            const SizedBox(height: 25),
            _buildSaveButton(),
            const Divider(height: 40, thickness: 2),
            const Text("الشركات المسجلة حالياً:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            _buildManufacturersList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNameInput() {
    return TextField(
      controller: _nameController,
      textAlign: TextAlign.right,
      decoration: const InputDecoration(
        labelText: "اسم الشركة / المصنع",
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.business)
      )
    );
  }

  Widget _buildSubCategorySelector() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('subCategory').orderBy('order').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: snapshot.data!.docs.map((doc) {
            final isSelected = _selectedSubCategoryIds.contains(doc.id);
            return FilterChip(
              label: Text(doc['name']),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedSubCategoryIds.add(doc.id);
                  } else {
                    _selectedSubCategoryIds.remove(doc.id);
                  }
                });
              },
              selectedColor: Colors.blue[100],
              checkmarkColor: Colors.blue,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildLogoPicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150, width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border.all(color: Colors.blue[200]!, width: 2),
          borderRadius: BorderRadius.circular(12)
        ),
        child: _selectedImage == null
          ? const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_upload, size: 40, color: Colors.blue),
                Text("رفع شعار الشركة (Logo)"),
              ],
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: kIsWeb 
                ? Image.network(_selectedImage!.path, fit: BoxFit.contain)
                : Image.file(io.File(_selectedImage!.path), fit: BoxFit.contain),
            ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveManufacturer,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 55),
        backgroundColor: const Color(0xFF4361ee),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
      ),
      child: _isLoading
        ? const CircularProgressIndicator(color: Colors.white)
        : const Text("حفظ الشركة والبيانات", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildManufacturersList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('manufacturers').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (context, index) => const Divider(),
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 50, height: 50,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    data['imageUrl'] ?? '',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_not_supported),
                  ),
                ),
              ),
              title: Text(data['name'] ?? 'بدون اسم', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("مرتبطة بـ ${(data['subCategoryIds'] as List?)?.length ?? 0} أقسام"),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmDelete(doc.id, data['imagePublicId'])
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDelete(String docId, String? storagePath) async {
    // كود الحذف من Firestore و Storage لضمان النظافة
    await FirebaseFirestore.instance.collection('manufacturers').doc(docId).delete();
    if (storagePath != null) {
      try {
        await FirebaseStorage.instance.ref().child(storagePath).delete();
      } catch (e) {
        debugPrint("Error deleting logo: $e");
      }
    }
    _showSuccessSnackBar("تم حذف الشركة");
  }
}


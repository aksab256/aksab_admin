// المسار: lib/widgets/sub_category_tab.dart
import 'package:flutter/foundation.dart' show kIsWeb; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io' as io;

class SubCategoryTab extends StatefulWidget {
  const SubCategoryTab({super.key});

  @override
  State<SubCategoryTab> createState() => _SubCategoryTabState();
}

class _SubCategoryTabState extends State<SubCategoryTab> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _selectedMainId;
  XFile? _selectedImage;
  String? _existingImageUrl;
  String? _editingDocId;
  bool _isLoading = false;

  // --- 1. التقاط الصورة ---
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = pickedFile;
        _existingImageUrl = null;
      });
    }
  }

  // --- 2. محرك الرفع الموحد (السر في الـ Bytes) ---
  Future<Map<String, String>?> _uploadToFirebase(XFile xFile) async {
    try {
      // المسار في الـ Storage لضمان التنظيم
      String fileName = 'subCategoryImages/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // 🎯 أهم خطوة: تحويل الملف لـ Bytes لضمان التوافق مع الويب والموبايل معاً
      final bytes = await xFile.readAsBytes();
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

      // استخدام putData بدلاً من putFile لتفادي مشاكل الـ CORS والمسارات الوهمية في الويب
      UploadTask uploadTask = storageRef.putData(bytes, metadata);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return {
        'url': downloadUrl,
        'public_id': fileName
      };
    } catch (e) {
      debugPrint("❌ Upload Error: $e");
      return null;
    }
  }

  // --- 3. حفظ البيانات (مع الحفاظ على الحقول الأصلية بدقة) ---
  Future<void> _saveSubCategory() async {
    if (_nameController.text.isEmpty || _selectedMainId == null || (_selectedImage == null && _existingImageUrl == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("أكمل البيانات: الاسم، القسم، والصورة")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? finalUrl = _existingImageUrl;
      String? finalPublicId;

      if (_selectedImage != null) {
        final uploadResult = await _uploadToFirebase(_selectedImage!);
        if (uploadResult != null) {
          finalUrl = uploadResult['url'];
          finalPublicId = uploadResult['public_id'];
        } else {
          throw Exception("فشل رفع الصورة للسيرفر");
        }
      }

      // ⚠️ تحذير: لا تغير أسماء هذه المفاتيح (Keys) أبداً لضمان عمل الفرونت إند
      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'mainId': _selectedMainId,
        'order': int.tryParse(_orderController.text) ?? 0,
        'imageUrl': finalUrl,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // إضافة الـ Public ID فقط إذا تم رفع صورة جديدة
      if (finalPublicId != null) data['imagePublicId'] = finalPublicId;

      if (_editingDocId != null) {
        await FirebaseFirestore.instance.collection('subCategory').doc(_editingDocId).update(data);
        _showSuccessSnackBar("تم التحديث بنجاح");
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('subCategory').add(data);
        _showSuccessSnackBar("تمت الإضافة بنجاح");
        _clearForm();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          children: [
            _buildFormCard(),
            const Divider(height: 40),
            _buildDataList(),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Column(
      children: [
        TextField(controller: _nameController, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "اسم القسم الفرعي", border: OutlineInputBorder())),
        const SizedBox(height: 15),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('mainCategory').orderBy('order').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return DropdownButtonFormField<String>(
              value: _selectedMainId,
              hint: const Text("اختر القسم الرئيسي الرئيسي"),
              isExpanded: true,
              items: snapshot.data!.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
              onChanged: (val) => setState(() => _selectedMainId = val),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            );
          },
        ),
        const SizedBox(height: 15),
        TextField(controller: _orderController, keyboardType: TextInputType.number, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "رقم الترتيب", border: OutlineInputBorder())),
        const SizedBox(height: 15),
        _buildImagePickerPreview(),
        const SizedBox(height: 20),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildImagePickerPreview() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150, width: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: Colors.blue[200]!), borderRadius: BorderRadius.circular(10), color: Colors.grey[50]),
        child: (_selectedImage == null && _existingImageUrl == null)
            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 40, color: Colors.blue), Text("اضغط لرفع الصورة")])
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _selectedImage != null
                    ? (kIsWeb ? Image.network(_selectedImage!.path, fit: BoxFit.cover) : Image.file(io.File(_selectedImage!.path), fit: BoxFit.cover))
                    : Image.network(_existingImageUrl!, fit: BoxFit.cover),
              ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (_editingDocId != null)
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: ElevatedButton(onPressed: _clearForm, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text("إلغاء", style: TextStyle(color: Colors.white))))),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveSubCategory,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: const Color(0xFF4361ee)),
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_editingDocId == null ? "إضافة قسم فرعي" : "تحديث البيانات", style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ),
      ],
    );
  }

  Widget _buildDataList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('subCategory').orderBy('order').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.network(data['imageUrl'] ?? "", width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
                ),
                title: Text(data['name'] ?? ""),
                subtitle: Text("الترتيب: ${data['order']}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _prepareUpdate(doc)),
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _confirmDelete(doc.id, data['imagePublicId'])),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- وظائف مساعدة ---
  void _prepareUpdate(DocumentSnapshot doc) {
    setState(() {
      _editingDocId = doc.id;
      _nameController.text = doc['name'] ?? "";
      _orderController.text = (doc['order'] ?? 0).toString();
      _selectedMainId = doc['mainId'];
      _existingImageUrl = doc['imageUrl'];
      _selectedImage = null;
    });
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  void _clearForm() {
    _nameController.clear();
    _orderController.clear();
    setState(() {
      _editingDocId = null;
      _selectedImage = null;
      _selectedMainId = null;
      _existingImageUrl = null;
    });
  }

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  Future<void> _confirmDelete(String docId, String? storagePath) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text("تأكيد الحذف"),
          content: const Text("هل أنت متأكد من حذف هذا القسم الفرعي؟"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("إلغاء")),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("حذف الآن", style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('subCategory').doc(docId).delete();
      if (storagePath != null && storagePath.startsWith('subCategoryImages/')) {
        try {
          await FirebaseStorage.instance.ref().child(storagePath).delete();
        } catch (e) {
          debugPrint("Error deleting image: $e");
        }
      }
      _showSuccessSnackBar("تم الحذف بنجاح");
    }
  }
}


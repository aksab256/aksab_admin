// المسار: lib/widgets/sub_category_tab.dart
import 'package:flutter/foundation.dart' show kIsWeb; // 🚀 للاستخدام الذكي للويب
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

  String? _selectedMainId;
  XFile? _selectedImage;
  String? _existingImageUrl;
  String? _editingDocId;
  bool _isLoading = false;

  // --- التقاط الصورة ---
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

  // --- محرك الرفع المتوافق مع معايير بلازا (التعديل الجوهري) ---
  Future<Map<String, String>?> _uploadToFirebase(XFile xFile) async {
    try {
      String fileName = 'subCategoryImages/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // تأمين الميتا داتا لضمان العرض المباشر في المتصفح
      SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploaded_by': 'aksab_admin'},
      );

      UploadTask uploadTask;
      
      // 🚀 الحل السحري للتوافق: التمييز بين الويب والموبايل
      if (kIsWeb) {
        // للويب: نستخدم Bytes مباشرة لتفادي مشاكل المسارات الوهمية
        final bytes = await xFile.readAsBytes();
        uploadTask = storageRef.putData(bytes, metadata);
      } else {
        // للموبايل: نستخدم File كالعادة
        uploadTask = storageRef.putFile(io.File(xFile.path), metadata);
      }

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return {
        'url': downloadUrl,
        'public_id': fileName
      };
    } catch (e) {
      debugPrint("Upload Error: $e");
      return null;
    }
  }

  // --- حفظ البيانات (إضافة/تحديث) ---
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
        }
      }

      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'mainId': _selectedMainId,
        'order': int.tryParse(_orderController.text) ?? 0,
        'imageUrl': finalUrl,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (finalPublicId != null) data['imagePublicId'] = finalPublicId;

      if (_editingDocId != null) {
        await FirebaseFirestore.instance.collection('subCategory').doc(_editingDocId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('subCategory').add(data);
      }

      _clearForm();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تمت العملية بنجاح")));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- حذف القسم وصورته ---
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم الحذف بنجاح")));
    }
  }

  void _prepareUpdate(DocumentSnapshot doc) {
    setState(() {
      _editingDocId = doc.id;
      _nameController.text = doc['name'];
      _orderController.text = doc['order'].toString();
      _selectedMainId = doc['mainId'];
      _existingImageUrl = doc['imageUrl'];
      _selectedImage = null;
    });
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // 🎯 الحفاظ على النسق العربي
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ... (نفس الـ UI الجميل بتاعك مع تحسينات طفيفة لعرض الصور)
            _buildForm(),
            const Divider(height: 40),
            _buildList(),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
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
              hint: const Text("اختر القسم الرئيسي"),
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
        _buildImagePickerBox(),
        const SizedBox(height: 20),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildImagePickerBox() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150, width: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: Colors.blue[200]!), borderRadius: BorderRadius.circular(10)),
        child: (_selectedImage == null && _existingImageUrl == null)
            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 40), Text("اضغط لرفع الصورة")])
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _selectedImage != null
                    ? (kIsWeb ? Image.network(_selectedImage!.path) : Image.file(io.File(_selectedImage!.path), fit: BoxFit.cover))
                    : Image.network(_existingImageUrl!, fit: BoxFit.cover),
              ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Row(
      children: [
        if (_editingDocId != null)
          Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: ElevatedButton(onPressed: _clearForm, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text("إلغاء")))),
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

  Widget _buildList() {
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
                  child: Image.network(data['imageUrl'], width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
                ),
                title: Text(data['name']),
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
}


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io' as io;

class MainCategoryTab extends StatefulWidget {
  const MainCategoryTab({super.key});

  @override
  State<MainCategoryTab> createState() => _MainCategoryTabState();
}

class _MainCategoryTabState extends State<MainCategoryTab> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  XFile? _selectedImage;
  String? _existingImageUrl;
  String? _editingDocId;
  bool _isLoading = false;
  bool _isForConsumer = false;

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

  void _prepareUpdate(DocumentSnapshot doc) {
    setState(() {
      _editingDocId = doc.id;
      _nameController.text = doc['name'] ?? "";
      _orderController.text = (doc['order'] ?? 0).toString();
      _existingImageUrl = doc['imageUrl'];
      _selectedImage = null;

      final data = doc.data() as Map<String, dynamic>;
      final behavior = data.containsKey('offerBehavior') ? data['offerBehavior'] : "";
      _isForConsumer = (behavior == "supermarket_offers");
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  void _resetForm() {
    setState(() {
      _editingDocId = null;
      _nameController.clear();
      _orderController.clear();
      _selectedImage = null;
      _existingImageUrl = null;
      _isForConsumer = false;
    });
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 60),
            const SizedBox(height: 15),
            Text(msg, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("تم"))],
      ),
    );
  }

  // 🚀 المحرك الموحد والآمن: يعتمد على الـ Bytes مع اسم ملف نظيف
  Future<Map<String, String>?> _uploadToFirebase(XFile xFile) async {
    try {
      // استخدام Timestamp كاسم للملف لتجنب مشاكل الرموز والمسافات في الويب
      String fileName = 'main_categories/${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // قراءة الملف كـ Bytes لضمان عمله على الويب والموبايل
      final bytes = await xFile.readAsBytes();
      
      // تأمين نوع الملف (Metadata) لضمان القبول من السيرفر
      SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'origin': 'aksab_admin_web'},
      );

      // الرفع الآمن باستخدام putData
      UploadTask uploadTask = storageRef.putData(bytes, metadata);

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return {
        'url': downloadUrl,
        'public_id': fileName
      };
    } catch (e) {
      debugPrint("❌ Detailed Upload Error: $e");
      return null;
    }
  }

  Future<void> _saveMainCategory() async {
    if (_nameController.text.isEmpty || (_selectedImage == null && _existingImageUrl == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إدخال الاسم والصورة")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? finalImageUrl = _existingImageUrl;
      String? finalPublicId;

      if (_selectedImage != null) {
        final uploadResult = await _uploadToFirebase(_selectedImage!);
        if (uploadResult != null) {
          finalImageUrl = uploadResult['url'];
          finalPublicId = uploadResult['public_id'];
        } else {
          throw Exception("فشل رفع الصورة.. تأكد من اتصال الإنترنت");
        }
      }

      final Map<String, dynamic> data = {
        'name': _nameController.text.trim(),
        'order': int.tryParse(_orderController.text) ?? 0,
        'imageUrl': finalImageUrl,
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'offerBehavior': _isForConsumer ? "supermarket_offers" : "",
      };

      if (finalPublicId != null) data['imagePublicId'] = finalPublicId;

      if (_editingDocId != null) {
        await FirebaseFirestore.instance.collection('mainCategory').doc(_editingDocId).update(data);
        _showSuccessDialog("تم تحديث القسم بنجاح");
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('mainCategory').add(data);
        _showSuccessDialog("تم إضافة القسم بنجاح");
        _resetForm();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: ${e.toString()}")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(controller: _nameController, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "اسم القسم الرئيسي", border: OutlineInputBorder())),
          const SizedBox(height: 15),
          TextField(controller: _orderController, keyboardType: TextInputType.number, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الترتيب", border: OutlineInputBorder())),
          const SizedBox(height: 15),
          CheckboxListTile(
            title: const Text("متاح للمستهلك (عروض سوبر ماركت)", textAlign: TextAlign.right),
            value: _isForConsumer,
            activeColor: const Color(0xFF4361ee),
            onChanged: (val) => setState(() => _isForConsumer = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 150, width: double.infinity,
              decoration: BoxDecoration(border: Border.all(color: Colors.blue[200]!), borderRadius: BorderRadius.circular(10)),
              child: (_selectedImage == null && _existingImageUrl == null)
                  ? const Center(child: Text("اضغط لرفع صورة القسم الرئيسي"))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _selectedImage != null
                          ? (kIsWeb
                              ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                              : Image.file(io.File(_selectedImage!.path), fit: BoxFit.cover))
                          : Image.network(_existingImageUrl!, fit: BoxFit.cover),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (_editingDocId != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ElevatedButton(
                      onPressed: _resetForm,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                      child: const Text("إلغاء التعديل", style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveMainCategory,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4361ee)),
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_editingDocId == null ? "حفظ القسم الرئيسي" : "تحديث البيانات الآن", style: const TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
          const Divider(height: 40),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('mainCategory').orderBy('order').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var doc = snapshot.data!.docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  bool isPromo = (data.containsKey('offerBehavior') && data['offerBehavior'] == "supermarket_offers");
                  String? imgUrl = data['imageUrl'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey[200],
                      backgroundImage: (imgUrl != null && imgUrl.isNotEmpty)
                          ? NetworkImage(imgUrl)
                          : null,
                      child: (imgUrl == null || imgUrl.isEmpty) ? const Icon(Icons.image) : null,
                    ),
                    title: Text(doc['name'] ?? "بدون اسم"),
                    subtitle: Text("ترتيب: ${doc['order']} ${isPromo ? ' | 🎁 عرض' : ''}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _prepareUpdate(doc)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _showDeleteDialog(doc.id, data['imagePublicId'])),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(String id, String? storagePath) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تنبيه الحذف"),
        content: const Text("هل أنت متأكد من حذف هذا القسم نهائياً مع صورته؟"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('mainCategory').doc(id).delete();
              if (storagePath != null && storagePath.isNotEmpty) {
                try {
                  await FirebaseStorage.instance.ref().child(storagePath).delete();
                } catch (e) {
                  debugPrint("Error deleting image: $e");
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}


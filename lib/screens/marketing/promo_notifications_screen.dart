import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 🚀 بديل Cloudinary
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class PromoNotificationsScreen extends StatefulWidget {
  const PromoNotificationsScreen({super.key});

  @override
  State<PromoNotificationsScreen> createState() => _PromoNotificationsScreenState();
}

class _PromoNotificationsScreenState extends State<PromoNotificationsScreen> {
  // 🎯 تم الاستغناء عن روابط AWS Lambda نهائياً
  // الـ Topics المعتمدة في مشروع "رابية أحلى"
  final List<String> _topics = ['all_users', 'retailers', 'consumers', 'drivers', 'test_topic'];
  
  final TextEditingController _titleCtrl = TextEditingController(text: "أكسب 💰");
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _imgUrlCtrl = TextEditingController();

  String? _selectedTopic = 'all_users';
  String _selectedSound = 'default';
  String _targetScreen = 'Home';
  bool _isLoading = false;
  bool _isUploading = false;

  // 🎯 دالة الرفع المعتمدة لـ Firebase Storage (نفس سيستم البانرات)
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() => _isUploading = true);
      try {
        String fileName = 'promo_notifs/${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}';
        Reference storageRef = FirebaseStorage.instance.ref().child(fileName);
        
        final bytes = await pickedFile.readAsBytes();
        SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

        UploadTask uploadTask = storageRef.putData(bytes, metadata);
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();

        setState(() {
          _imgUrlCtrl.text = downloadUrl;
        });
        _showSnackBar("تم رفع الصورة لبلازا بنجاح", Colors.green);
      } catch (e) {
        _showSnackBar("خطأ أثناء الرفع لـ Firebase", Colors.red);
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  // 🎯 دالة الإرسال المباشر (تخطي AWS)
  // ملاحظة: يفضل مستقبلاً وضع هذه الدالة في Cloud Function لزيادة الأمان
  Future<void> _sendNotification() async {
    if (_selectedTopic == null || _msgCtrl.text.isEmpty) {
      _showSnackBar("يرجى كتابة نص الرسالة واختيار الجمهور", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // هنا بنسجل الإشعار في الـ Firestore كـ Log للرجوع إليه (أفضل من AWS)
      await FirebaseFirestore.instance.collection('notifications_history').add({
        'topic': _selectedTopic,
        'title': _titleCtrl.text,
        'message': _msgCtrl.text,
        'image': _imgUrlCtrl.text,
        'sound': _selectedSound,
        'targetScreen': _targetScreen,
        'sentAt': FieldValue.serverTimestamp(),
      });

      // ⚠️ تنبيه: لإرسال الإشعار فعلياً بدون AWS، ستحتاج لاستخدام FCM v1 API
      // حالياً، سنقوم بحفظ الطلب في Firestore وستقوم وظيفة (Background Worker) بالإرسال
      // أو يمكننا استخدام مكتبة مباشرة إذا كنت تملك مفتاح الخدمة (Service Account)
      
      _showSnackBar("تم جدولة الإشعار للإرسال بنجاح!", Colors.green);
      _msgCtrl.clear();
      _imgUrlCtrl.clear();
    } catch (e) {
      _showSnackBar("حدث خطأ في النظام"، Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: color)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEEF2F5),
      appBar: AppBar(
        title: const Text("إرسال إشعار ترويجي (بلازا)", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        backgroundColor: const Color(0xFF1A2C3D),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel("اختر الجمهور المستهدف:"),
                  DropdownButtonFormField<String>(
                    value: _selectedTopic,
                    items: _topics.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) => setState(() => _selectedTopic = val),
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 15),
                  _buildLabel("عنوان الإشعار:"),
                  TextField(controller: _titleCtrl, decoration: _inputDecoration()),
                  const SizedBox(height: 15),
                  _buildLabel("نص الرسالة:"),
                  TextField(controller: _msgCtrl, maxLines: 3, decoration: _inputDecoration(hint: "اكتب رسالتك هنا...")),
                  const SizedBox(height: 15),
                  _buildLabel("صورة الإشعار:"),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _imgUrlCtrl,
                          decoration: _inputDecoration(hint: "رابط الصورة من بلازا...")
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isUploading ? null : _pickAndUploadImage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey,
                          padding: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                        child: _isUploading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.cloud_upload, color: Colors.white),
                      )
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildLabel("اختر النغمة المتكلمة:"),
                  DropdownButtonFormField<String>(
                    value: _selectedSound,
                    items: const [
                      DropdownMenuItem(value: 'default', child: Text("الافتراضية")),
                      DropdownMenuItem(value: 'order_new', child: Text("نغمة: طلب جديد")),
                      DropdownMenuItem(value: 'order_cancel', child: Text("نغمة: إلغاء طلب")),
                      DropdownMenuItem(value: 'promo_msg', child: Text("نغمة: عرض ترويجي")),
                      DropdownMenuItem(value: 'wallet_add', child: Text("نغمة: شحن محفظة")),
                      DropdownMenuItem(value: 'urgent_alert', child: Text("نغمة: تنبيه عاجل")),
                    ],
                    onChanged: (val) => setState(() => _selectedSound = val!),
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 15),
                  _buildLabel("عند الضغط يفتح صفحة:"),
                  DropdownButtonFormField<String>(
                    value: _targetScreen,
                    items: const [
                      DropdownMenuItem(value: 'Home', child: Text("الرئيسية")),
                      DropdownMenuItem(value: 'Orders', child: Text("قائمة الطلبات")),
                      DropdownMenuItem(value: 'Wallet', child: Text("المحفظة")),
                      DropdownMenuItem(value: 'Offers', child: Text("صفحة العروض")),
                    ],
                    onChanged: (val) => setState(() => _targetScreen = val!),
                    decoration: _inputDecoration(),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _sendNotification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("إرسال عبر بلازا", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    fillColor: const Color(0xFFF9F9F9),
    filled: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.deepPurple, width: 2)),
  );

  Widget _buildLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, right: 5),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
  );
}


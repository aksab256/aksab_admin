import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PromoNotificationsScreen extends StatefulWidget {
  const PromoNotificationsScreen({super.key});

  @override
  State<PromoNotificationsScreen> createState() => _PromoNotificationsScreenState();
}

class _PromoNotificationsScreenState extends State<PromoNotificationsScreen> {
  final CollectionReference _topicsRef = FirebaseFirestore.instance.collection('notification_topics');
  
  final TextEditingController _titleCtrl = TextEditingController(text: "أكسب 💰");
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _imgUrlCtrl = TextEditingController();

  String? _selectedTopic; 
  String _selectedSound = 'default';
  String _targetScreen = 'Home';
  bool _isLoading = false;
  bool _isUploading = false;

  // 1. رفع الصور لـ Firebase Storage (بلازا)
  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() => _isUploading = true);
      try {
        String fileName = 'promo_notifs/${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference storageRef = FirebaseStorage.instance.ref().child(fileName);
        await storageRef.putData(await pickedFile.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
        String url = await storageRef.getDownloadURL();
        setState(() => _imgUrlCtrl.text = url);
        _showSnackBar("تم رفع الصورة بنجاح", Colors.green);
      } catch (e) {
        _showSnackBar("خطأ في الرفع: $e", Colors.red);
      } finally {
        setState(() => _isUploading = false);
      }
    }
  }

  // 2. إرسال البيانات للـ Firestore (الـ Trigger)
  Future<void> _sendNotification() async {
    if (_selectedTopic == null || _msgCtrl.text.isEmpty) {
      _showSnackBar("اكمل البيانات أولاً", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('push_notifications').add({
        'topic': _selectedTopic, // سيتم استخدامه في Cloud Function
        'title': _titleCtrl.text,
        'message': _msgCtrl.text,
        'image': _imgUrlCtrl.text,
        'sound': _selectedSound,
        'data': {'screen': _targetScreen},
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      _showSnackBar("جاري معالجة الإرسال عبر السحابة", Colors.green);
      _msgCtrl.clear();
      _imgUrlCtrl.clear();
    } catch (e) {
      _showSnackBar("خطأ في النظام: $e", Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        title: const Text("مركز الإشعارات الذكي", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A2C3D),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildMainCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel("الجمهور المستهدف (من السحابة):"),
          StreamBuilder<QuerySnapshot>(
            stream: _topicsRef.snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return DropdownButtonFormField<String>(
                value: _selectedTopic,
                hint: const Text("اختر المجموعة المستهدفة"),
                items: snapshot.data!.docs.map((doc) {
                  return DropdownMenuItem(value: doc.id, child: Text(doc['name']));
                }).toList(),
                onChanged: (val) => setState(() => _selectedTopic = val),
                decoration: _inputDecoration(),
              );
            },
          ),
          const SizedBox(height: 20),
          _buildLabel("محتوى الإشعار:"),
          TextField(controller: _titleCtrl, decoration: _inputDecoration(hint: "العنوان")),
          const SizedBox(height: 10),
          TextField(controller: _msgCtrl, maxLines: 3, decoration: _inputDecoration(hint: "نص الرسالة...")),
          const SizedBox(height: 20),
          _buildLabel("الوسائط (Firebase Storage):"),
          Row(
            children: [
              Expanded(child: TextField(controller: _imgUrlCtrl, decoration: _inputDecoration(hint: "رابط الصورة"))),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _isUploading ? null : _pickAndUploadImage,
                icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_a_photo),
              ),
            ],
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendNotification,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A2C3D), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("إرسال الإشعار الآن", style: TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'Cairo')),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
  );

  Widget _buildLabel(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')));

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: color));
  }
}


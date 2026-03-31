import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; // الضيف الجديد

class CloudinaryService {
  // القيم دي هنخليها عشان لو فيه ملفات تانية بتناديها ما تضربش Error
  static const String uploadPreset = "commerce"; 
  static const String cloudName = "dgmmx6jbu";

  static Future<Map<String, String>?> uploadImage(XFile xFile) async {
    try {
      print("🚀 تحويل الرفع من كلوديناري إلى بلازا ستورج...");
      
      // 1. تجهيز المسار واسم الملف
      String fileName = 'uploads/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // 2. قراءة الملف كـ Bytes (مناسب للويب والموبايل)
      final bytes = await xFile.readAsBytes();

      // 3. الرفع الفعلي لـ Firebase
      UploadTask uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 4. انتظار الإتمام والحصول على الرابط
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      print("✅ تم الرفع بنجاح لـ بلازا: $downloadUrl");

      // 5. نرجع الخريطة بنفس الشكل القديم عشان اللي بينادي ما يحسش بفرق
      return {
        "url": downloadUrl,
        "publicId": fileName // بنستخدم المسار كـ ID بديل
      };

    } catch (e) {
      print("❌ خطأ في رفع بلازا: $e");
      return null;
    }
  }
}


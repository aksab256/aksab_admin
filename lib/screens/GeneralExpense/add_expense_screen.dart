import 'dart:convert';
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';                     
import 'package:image_picker/image_picker.dart';
// ⬅️ استيراد الخدمة اللي عدلناها عشان تنادي بلازا
import '../../services/cloudinary_service.dart'; 
import 'dart:io' show File;                          

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override                                            
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();                                      
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _detailsController = TextEditingController();

  String _selectedSource = 'office';                   
  DateTime _selectedDate = DateTime.now();
  XFile? _imageFile; // تغيير النوع لـ XFile ليتوافق مع الخدمة الجديدة
  bool _isUploading = false;                         

  final Map<String, String> _expenseSources = {          
    'office': 'إيجار ومرافق المكتب',                     
    'salaries': 'مرتبات وحوافز',
    'marketing': 'تسويق وإعلانات',                       
    'maintenance': 'صيانة وتجهيزات',
    'other': 'مصاريف أخرى',                            
  };

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (pickedFile != null) {                              
      setState(() {
        _imageFile = pickedFile;                           
      });                                                
    }
  }

  // ✅ التعديل الجوهري: دالة الرفع أصبحت تنادي "بلازا" عبر السيرفيس
  Future<String?> _uploadToPlaza() async {          
    if (_imageFile == null) return null;

    try {
      // بننادي السيرفيس اللي "لغمناه" بـ Firebase Storage
      final response = await CloudinaryService.uploadImage(_imageFile!);
      if (response != null) {
        return response['url']; // الرابط الجديد من Firebase
      }
    } catch (e) {
      debugPrint("Plaza Upload Error: $e");         
    }
    return null;
  }                                                  

  Future<void> _saveExpense() async {                    
    if (!_formKey.currentState!.validate()) return;

    if (_imageFile == null) {                              
      ScaffoldMessenger.of(context).showSnackBar(            
        const SnackBar(content: Text("برجاء إرفاق صورة مستند المصروف 📸"), backgroundColor: Colors.orange),
      );                                                   
      return;
    }
                                                         
    setState(() => _isUploading = true);

    try {                                                  
      // 🚀 الرفع الآن يتم عبر بلازا ستورج
      String? imageUrl = await _uploadToPlaza();
      if (imageUrl == null) throw Exception("فشل رفع المستند للسحابة");                                                                                                       
      
      String periodLabel = DateFormat('yyyy-MM').format(_selectedDate);
      await FirebaseFirestore.instance.collection('platform_ledger').add({                                        
        'period': periodLabel,                               
        'entryType': 'expense',
        'source': _selectedSource,
        'totalAmount': double.parse(_amountController.text),
        'details': _detailsController.text,                  
        'attachmentUrl': imageUrl,                           
        'createdAt': Timestamp.fromDate(_selectedDate),                                                           
        'recordedBy': 'Admin',
      });                                                                                                       
      
      if (mounted) {
        setState(() => _isUploading = false);        
        HapticFeedback.heavyImpact();
        _showSuccessDialog();                              
      }                                                  
    } catch (e) {
      setState(() => _isUploading = false);                
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: Colors.red),
      );
    }                                                  
  }                                                  

  void _showSuccessDialog() {                            
    showDialog(
      context: context,                                    
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),                                   
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 70),
            const SizedBox(height: 15),
            const Text("تم الحفظ بنجاح ✅",
              style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("تم تسجيل المصروف وإرفاق المستند في السجلات المالية لشركة رابية أحلى.",
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),                    
          ],                                                 
        ),                                                   
        actions: [
          Center(                                                
            child: ElevatedButton(                                 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: StadiumBorder()),
              onPressed: () {
                _formKey.currentState!.reset();
                _amountController.clear();
                _detailsController.clear();                          
                setState(() {                                          
                  _imageFile = null;                                   
                  _selectedDate = DateTime.now();                    
                });                                                  
                Navigator.pop(context);                            
              },
              child: const Text("حسناً، إضافة مصروف آخر", style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),                                                 
          ),                                                 
        ],                                                 
      ),                                                 
    );                                                 
  }                                                                                                         

  @override
  Widget build(BuildContext context) {                   
    return Scaffold(                                       
      appBar: AppBar(                                        
        title: const Text("تسجيل مصروف بمستند", style: TextStyle(fontFamily: 'Cairo')),                           
        backgroundColor: const Color(0xFFB21F2D),            
        centerTitle: true,                                 
      ),
      body: _isUploading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [                         
              CircularProgressIndicator(color: Color(0xFFB21F2D)),                                                      
              SizedBox(height: 15),                                
              Text("جاري رفع المستند وتأمين القيد...", style: TextStyle(fontFamily: 'Cairo'))                         
            ]))                                                
          : SingleChildScrollView(                                 
              padding: const EdgeInsets.all(25),                   
              child: Form(                                           
                key: _formKey,                                       
                child: Column(                                         
                  children: [                                            
                    GestureDetector(                                       
                      onTap: () => _showImageSourceOptions(),                                                                   
                      child: Container(                                      
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(                             
                          color: Colors.grey[100],                             
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _imageFile == null ? Colors.red.shade300 : Colors.green.shade400, width: 2, style: BorderStyle.solid),                             
                        ),                                                   
                        child: _imageFile == null                                
                          ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [                                       
                              Icon(Icons.cloud_upload_outlined, size: 50, color: Colors.grey),                                          
                              SizedBox(height: 10),                                
                              Text("اضغط لإرفاق صورة المستند (إجباري)", style: TextStyle(fontFamily: 'Cairo', color: Colors.grey))                                                         
                            ])                                                 
                          : ClipRRect(                                             
                              borderRadius: BorderRadius.circular(18),                                                                  
                              child: kIsWeb
                                  ? Image.network(_imageFile!.path, fit: BoxFit.cover)
                                  : Image.file(File(_imageFile!.path), fit: BoxFit.cover),                                               
                            ),                                           
                      ),
                    ),
                    const SizedBox(height: 30),      
                    TextFormField(                                         
                      controller: _amountController,                       
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),                                       
                      style: const TextStyle(fontWeight: FontWeight.bold),                                                      
                      decoration: InputDecoration(                           
                        labelText: "القيمة المالية (ج.م)",                                                                        
                        prefixIcon: const Icon(Icons.monetization_on_outlined),                                                   
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),                                    
                      ),                                                   
                      validator: (value) => value!.isEmpty ? "يرجى إدخال القيمة" : null,                                      
                    ),                                                   
                    const SizedBox(height: 20),      
                    TextFormField(                                         
                      controller: _detailsController,                      
                      maxLines: 3,                                         
                      decoration: InputDecoration(
                        labelText: "بيان المصروف (التفاصيل)",                                                                     
                        prefixIcon: const Icon(Icons.description_outlined),                                                       
                        alignLabelWithHint: true,                            
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                      ),                                                   
                      validator: (value) => value!.isEmpty ? "يرجى كتابة وصف للمصروف" : null,                                 
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(                       
                      value: _selectedSource,                              
                      decoration: InputDecoration(                           
                        labelText: "نوع المصروف",                            
                        prefixIcon: const Icon(Icons.category_outlined),                                                          
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),                                    
                      ),                                                   
                      items: _expenseSources.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontFamily: 'Cairo')))).toList(),                                                              
                      onChanged: (val) => setState(() => _selectedSource = val!),                                             
                    ),                                                   
                    const SizedBox(height: 20),                                                                               
                    ListTile(                                              
                      title: Text("تاريخ العملية: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}", style: const TextStyle(fontFamily: 'Cairo')),                                  
                      trailing: const Icon(Icons.edit_calendar),                                                                
                      onTap: () async {                                      
                        DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                        if (picked != null) setState(() => _selectedDate = picked);
                      },
                      tileColor: Colors.white,                             
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade300)),
                    ),                                                   
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 60,                                          
                      child: ElevatedButton.icon(                            
                        onPressed: _saveExpense,                             
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text("تأكيد وحفظ البيانات", style: TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),                                                                    
                        style: ElevatedButton.styleFrom(                                                                            
                          backgroundColor: const Color(0xFFB21F2D),                                                                 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),                                   
                          elevation: 3,                                      
                        ),                                                 
                      ),                                                 
                    ),
                  ],                                                 
                ),
              ),                                                 
            ),
    );                                                 
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(                                  
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),       
      builder: (context) => SafeArea(                        
        child: Wrap(
          children: [                                            
            const Padding(
              padding: EdgeInsets.all(15.0),                       
              child: Text("اختيار مصدر الصورة", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
            ),                                                   
            ListTile(leading: const Icon(Icons.camera_alt, color: Color(0xFFB21F2D)), title: const Text("التقاط بالكاميرا", style: TextStyle(fontFamily: 'Cairo')), onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),                                          
            ListTile(leading: const Icon(Icons.photo_library, color: Color(0xFFB21F2D)), title: const Text("من معرض الصور", style: TextStyle(fontFamily: 'Cairo')), onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
            const SizedBox(height: 10),                        
          ],
        ),
      ),
    );
  }
}


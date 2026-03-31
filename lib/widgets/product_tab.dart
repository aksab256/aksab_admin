// المسار: lib/widgets/product_tab.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import '../pages/products_report_page.dart';
import 'excel_import_service.dart';

class ProductTab extends StatefulWidget {
  const ProductTab({super.key});

  @override
  State<ProductTab> createState() => _ProductTabState();
}

class _ProductTabState extends State<ProductTab> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _orderController = TextEditingController();
  final _unitController = TextEditingController();
  final _factorController = TextEditingController(text: "1");
  final _barcodeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? selectedMainId;
  String? selectedSubId;
  String? selectedManufacturerId;
  String status = 'active';

  // دعم 4 صور للمنتج
  List<XFile?> selectedImages = [null, null, null, null];
  List<Map<String, dynamic>> unitsWithFactors = [];
  bool _isLoading = false;

  // --- 1. التقاط الصور ---
  Future<void> _pickImage(int index) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => selectedImages[index] = image);
    }
  }

  // --- 2. محرك الرفع الموحد (السر في الـ Bytes) ---
  Future<Map<String, String>?> _uploadToFirebase(XFile xFile) async {
    try {
      String fileName = 'productImages/${DateTime.now().millisecondsSinceEpoch}_${xFile.name}';
      Reference storageRef = FirebaseStorage.instance.ref().child(fileName);

      // قراءة الملف كـ Bytes لضمان التوافق التام (ويب + موبايل)
      final bytes = await xFile.readAsBytes();
      SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');

      // استخدام putData لتفادي مشاكل الـ CORS والمسارات الوهمية
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

  // --- 3. حفظ المنتج النهائي ---
  Future<void> _saveProduct() async {
    // التحقق من البيانات الأساسية (الاسم، الأقسام، الشركة، الصورة الأولى، والوحدات)
    if (_nameController.text.isEmpty || 
        selectedMainId == null || 
        selectedSubId == null ||
        selectedManufacturerId == null || 
        selectedImages[0] == null || 
        unitsWithFactors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("يرجى إكمال كافة البيانات (الاسم، الأقسام، الصورة الأولى، والوحدات)")));
      return;
    }

    setState(() => _isLoading = true);
    try {
      List<String> imageUrls = [];
      List<String> imagePublicIds = [];

      // رفع الصور المختارة فقط من الـ 4 مصفوفات
      for (var img in selectedImages) {
        if (img != null) {
          final result = await _uploadToFirebase(img);
          if (result != null) {
            imageUrls.add(result['url']!);
            imagePublicIds.add(result['public_id']!);
          } else {
            throw Exception("فشل رفع إحدى صور المنتج");
          }
        }
      }

      // ⚠️ الحفاظ على هيكلية الحقول بدقة كما في "أكسب" القديم
      await FirebaseFirestore.instance.collection('products').add({
        'name': _nameController.text.trim(),
        'barcode': _barcodeController.text.trim(),
        'description': _descController.text.trim(),
        'mainId': selectedMainId,
        'subId': selectedSubId,
        'manufacturerId': selectedManufacturerId,
        'order': int.tryParse(_orderController.text) ?? 0,
        'status': status,
        'imageUrls': imageUrls,
        'imagePublicIds': imagePublicIds,
        'units': unitsWithFactors, // الوحدات للعرض
        'unitsWithFactors': unitsWithFactors, // الوحدات للحسابات (تكرار للأمان)
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _resetForm();
      if (mounted) {
        _showSuccessDialog("تم إضافة المنتج بنجاح بنظام بلازا الموحد");
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الحفظ: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- وظائف مساعدة ---
  void _addUnit() {
    if (_unitController.text.isNotEmpty) {
      setState(() {
        unitsWithFactors.add({
          'unitName': _unitController.text.trim(),
          'subQty': int.tryParse(_factorController.text) ?? 1
        });
        _unitController.clear();
        _factorController.text = "1";
      });
    }
  }

  void _resetForm() {
    _nameController.clear();
    _descController.clear();
    _orderController.clear();
    _barcodeController.clear();
    _unitController.clear();
    _factorController.text = "1";
    setState(() {
      selectedImages = [null, null, null, null];
      unitsWithFactors = [];
      selectedSubId = null;
      selectedMainId = null;
      selectedManufacturerId = null;
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
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("تم"))],
      ),
    );
  }

  // --- واجهة المستخدم (UI) ---
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
            _buildHeaderLinks(),
            const SizedBox(height: 20),
            _buildMainInputs(),
            const SizedBox(height: 20),
            const Text("صور المنتج (الصورة الأولى إجبارية)", style: TextStyle(fontWeight: FontWeight.bold)),
            _buildImagesGrid(),
            const SizedBox(height: 20),
            const Text("وحدات البيع والمعامل (مثل: كرتونة تحتوي 12 قطعة)", style: TextStyle(fontWeight: FontWeight.bold)),
            _buildUnitSection(),
            const SizedBox(height: 30),
            _buildSaveButton(),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderLinks() {
    return Column(
      children: [
        InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProductsReportPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF4361ee).withOpacity(0.3))),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF4361ee)),
                Row(children: [Text("عرض كتالوج المنتجات", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4361ee))), SizedBox(width: 10), Icon(Icons.inventory_2_outlined, color: Color(0xFF4361ee))]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _importExcelWithImages,
          icon: const Icon(Icons.auto_awesome, color: Colors.white),
          label: const Text("استيراد (إكسل + صور)", style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, minimumSize: const Size(double.infinity, 45)),
        ),
      ],
    );
  }

  Widget _buildMainInputs() {
    return Column(
      children: [
        TextField(controller: _barcodeController, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "باركود المنتج (يدوي أو اسكنر)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.qr_code))),
        const SizedBox(height: 10),
        TextField(controller: _nameController, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "اسم المنتج", border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _descController, textAlign: TextAlign.right, maxLines: 2, decoration: const InputDecoration(labelText: "وصف المنتج", border: OutlineInputBorder())),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('mainCategory').orderBy('order').snapshots(),
          builder: (context, snapshot) => DropdownButtonFormField<String>(
            value: selectedMainId,
            hint: const Text("اختر القسم الرئيسي"),
            isExpanded: true,
            items: snapshot.data?.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
            onChanged: (val) => setState(() { selectedMainId = val; selectedSubId = null; }),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 10),
        if (selectedMainId != null)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('subCategory').where('mainId', isEqualTo: selectedMainId).snapshots(),
            builder: (context, snapshot) => DropdownButtonFormField<String>(
              value: selectedSubId,
              hint: const Text("اختر القسم الفرعي"),
              isExpanded: true,
              items: snapshot.data?.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
              onChanged: (val) => setState(() => selectedSubId = val),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('manufacturers').snapshots(),
          builder: (context, snapshot) => DropdownButtonFormField<String>(
            value: selectedManufacturerId,
            hint: const Text("اختر الشركة المصنعة"),
            isExpanded: true,
            items: snapshot.data?.docs.map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc['name']))).toList(),
            onChanged: (val) => setState(() => selectedManufacturerId = val),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 10),
        TextField(controller: _orderController, keyboardType: TextInputType.number, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "الترتيب", border: OutlineInputBorder())),
      ],
    );
  }

  Widget _buildImagesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5),
      itemCount: 4,
      itemBuilder: (context, index) => GestureDetector(
        onTap: () => _pickImage(index),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: index == 0 ? Colors.blue : Colors.grey[300]!), borderRadius: BorderRadius.circular(8), color: Colors.grey[50]),
          child: selectedImages[index] == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, color: index == 0 ? Colors.blue : Colors.grey), Text("صورة ${index + 1}", style: TextStyle(color: index == 0 ? Colors.blue : Colors.grey))])
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: kIsWeb 
                  ? Image.network(selectedImages[index]!.path, fit: BoxFit.cover)
                  : Image.file(io.File(selectedImages[index]!.path), fit: BoxFit.cover),
              ),
        ),
      ),
    );
  }

  Widget _buildUnitSection() {
    return Column(
      children: [
        Row(
          children: [
            IconButton(onPressed: _addUnit, icon: const Icon(Icons.add_circle, color: Colors.green, size: 30)),
            Expanded(child: TextField(controller: _unitController, textAlign: TextAlign.right, decoration: const InputDecoration(hintText: "اسم الوحدة (مثلاً: كرتونة)"))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _factorController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "المعامل (مثلاً: 12)"))),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: unitsWithFactors.map((u) => Chip(
          label: Text("${u['unitName']} (${u['subQty']})"),
          onDeleted: () => setState(() => unitsWithFactors.remove(u)),
          deleteIconColor: Colors.red,
        )).toList()),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveProduct,
      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: const Color(0xFF4361ee), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("حفظ المنتج النهائي", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  // استيراد الإكسل (يحتاج استدعاء الـ Service المجهز مسبقاً)
  Future<void> _importExcelWithImages() async {
    FilePickerResult? excelResult = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx']);
    if (excelResult == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الآن اختر جميع صور المنتجات من الاستوديو")));
    FilePickerResult? imagesResult = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
    if (imagesResult == null) return;
    setState(() => _isLoading = true);
    try {
      await ExcelImportService.importWithImages(context: context, excelFile: excelResult.files.first, imageFiles: imagesResult.files);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ أثناء الاستيراد: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}


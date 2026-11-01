// lib/widgets/seller_review_sheet.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_selector_sheet.dart';

class SellerReviewSheet extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final FirebaseFirestore? firestore;

  const SellerReviewSheet({super.key, required this.docId, required this.data, this.firestore});

  @override
  State<SellerReviewSheet> createState() => _SellerReviewSheetState();
}

class _SellerReviewSheetState extends State<SellerReviewSheet> {
  final TextEditingController _commissionRateController = TextEditingController();
  final TextEditingController _fixedCommissionController = TextEditingController();

  String _commissionType = "percentage"; 
  List<Map<String, dynamic>> _tempProducts = [];
  bool _isProcessing = false;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  String _f(dynamic val) => (val == null || val.toString().isEmpty) ? "غير متوفر" : val.toString();

  /// الدالة المصححة لمنع الـ null في قاعدة البيانات
  Future<void> _reject(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف طلب التاجر نهائيًا؟', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        content: const Text('سيُحذف الطلب من قائمة الانتظار كأن لم يكن، ولن يُرسل أي رمز.',
            textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isProcessing = true);
    try {
      await _db.collection('pendingSellers').doc(widget.docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الطلب نهائيًا', style: TextStyle(fontFamily: 'Cairo'))),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الحذف: $e')));
      }
    }
  }

  Future<void> _approve() async {
    setState(() => _isProcessing = true);
    try {
      final batch = _db.batch();
      final String sellerId = widget.docId;

      final sellerRef = _db.collection('sellers').doc(sellerId);
      final pendingRef = _db.collection('pendingSellers').doc(sellerId);

      // البيانات المالية
      double rate = double.tryParse(_commissionRateController.text) ?? 0;
      double monthlyFee = double.tryParse(_fixedCommissionController.text) ?? 0;

      // 1. تحديث بيانات التاجر في sellers
      batch.set(sellerRef, {
        ...widget.data,
        'status': 'active',
        'commissionType': _commissionType,
        'commissionRate': rate,
        'monthlyFee': monthlyFee,
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isVerified': true,
      });

      // 2. توزيع العروض (المنطق الذي يمنع الـ null)
      for (var offer in _tempProducts) {
        final String pId = offer['productId'] ?? '';
        if (pId.isEmpty) continue;

        final String offerId = "${sellerId}_$pId";
        final offerRef = _db.collection('productOffers').doc(offerId);

        // كتابة العرض مع التأكد من وجود كل الحقول المطلوبة كما في صورتك
        batch.set(offerRef, {
          'sellerId': sellerId,
          'sellerName': widget.data['merchantName'] ?? widget.data['fullname'] ?? "تاجر",
          'productId': pId,
          'productName': offer['productName'] ?? 'بدون اسم',
          'mainCategoryId': offer['mainCategoryId'] ?? '',
          'mainCategoryName': offer['mainCategoryName'] ?? '',
          'subCategoryId': offer['subCategoryId'] ?? '',
          'subCategoryName': offer['subCategoryName'] ?? '',
          'units': offer['units'] ?? [], // مصفوفة الوحدات والأسعار
          'imageUrl': offer['imageUrl'] ?? '',
          'status': 'active',
          'deliveryZones': [], // حقول فارغة افتراضية لتجنب الخطأ في تطبيق الزبون
          'deliveryAreas': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 3. حذف الطلب المعلق
      batch.delete(pendingRef);

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل الحساب ونشر العروض بنجاح')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("مراجعة واعتماد المورد", style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // الشعار
            if (widget.data['logoUrl'] != null)
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(widget.data['logoUrl']),
                ),
              ),
            const SizedBox(height: 20),

            _buildCard("البيانات الأساسية", [
              _row("الاسم التجاري", widget.data['merchantName']),
              _row("نوع النشاط", widget.data['businessType']),
              _row("اسم المسؤول", widget.data['fullname']),
              _row("رقم الهاتف", widget.data['phone']),
              _row("العنوان", widget.data['address']),
            ]),

            _buildCard("الوثائق والمستندات", [
              _buildImagePreview("السجل التجاري", widget.data['crUrl']),
              _buildImagePreview("البطاقة الضريبية", widget.data['tcUrl']),
            ]),

            _buildCard("إعدادات العمولة", [
              DropdownButtonFormField<String>(
                value: _commissionType,
                decoration: const InputDecoration(labelText: "نوع العمولة"),
                items: const [
                  DropdownMenuItem(value: "percentage", child: Text("نسبة مئوية فقط")),
                  DropdownMenuItem(value: "fixed", child: Text("مبلغ ثابت فقط")),
                  DropdownMenuItem(value: "both", child: Text("نسبة + مبلغ ثابت")),
                ],
                onChanged: (val) => setState(() => _commissionType = val!),
              ),
              const SizedBox(height: 15),
              if (_commissionType == "percentage" || _commissionType == "both")
                TextField(
                  controller: _commissionRateController,
                  decoration: const InputDecoration(labelText: "نسبة العمولة %", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              if (_commissionType == "both") const SizedBox(height: 10),
              if (_commissionType == "fixed" || _commissionType == "both")
                TextField(
                  controller: _fixedCommissionController,
                  decoration: const InputDecoration(labelText: "المبلغ الثابت / الرسوم (جنيه)", border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
            ]),

            const Divider(height: 40),

            // إضافة العروض من خلال الودجت الثانية
            _buildCard("إضافة العروض", [
              ProductSelectorSheet(
                onProductAdded: (p) {
                  setState(() => _tempProducts.add(p));
                },
                firestore: widget.firestore,
              ),
              if (_tempProducts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text("عدد المنتجات المضافة: ${_tempProducts.length}", 
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
            ]),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _isProcessing ? null : _approve,
                child: Text(
                  _isProcessing ? "جاري الحفظ..." : "تفعيل الحساب ونقل البيانات",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isProcessing ? null : () => _reject(context),
                child: const Text('رفض الطلب وحذفه نهائيًا',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- الودجت المساعدة ---
  Widget _buildImagePreview(String label, String? url) {
    if (url == null || url.isEmpty) return _row(label, "غير متوفر");
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          GestureDetector(
            onTap: () => showDialog(context: context, builder: (_) => Dialog(child: Image.network(url))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, height: 150, width: double.infinity, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const Divider(),
            ...children
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text("$label: ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Expanded(child: Text(_f(val), style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}


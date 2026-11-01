// lib/widgets/product_selector_sheet.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProductSelectorSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductAdded;
  final FirebaseFirestore? firestore;
  const ProductSelectorSheet({super.key, required this.onProductAdded, this.firestore});

  @override
  State<ProductSelectorSheet> createState() => _ProductSelectorSheetState();
}

class _ProductSelectorSheetState extends State<ProductSelectorSheet> {
  String? selectedMainCatId;
  String? selectedMainCatName; // جديد لحفظ الاسم
  String? selectedSubCatId;
  String? selectedSubCatName; // جديد لحفظ الاسم
  Map<String, dynamic>? selectedProduct;
  String? selectedUnit;

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("إضافة منتجات التاجر", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),

        // 1. القسم الرئيسي
        StreamBuilder<QuerySnapshot>(
          stream: (widget.firestore ?? FirebaseFirestore.instance).collection('mainCategory').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            return DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "القسم الرئيسي"),
              value: selectedMainCatId,
              items: snapshot.data!.docs.map((doc) {
                return DropdownMenuItem(
                  value: doc.id,
                  onTap: () => selectedMainCatName = doc['name'], // حفظ الاسم
                  child: Text(doc['name']),
                );
              }).toList(),
              onChanged: (val) => setState(() {
                selectedMainCatId = val;
                selectedSubCatId = null;
                selectedProduct = null;
                selectedUnit = null;
              }),
            );
          },
        ),

        // 2. القسم الفرعي
        if (selectedMainCatId != null)
          StreamBuilder<QuerySnapshot>(
            stream: (widget.firestore ?? FirebaseFirestore.instance).collection('subCategory')
                .where('mainId', isEqualTo: selectedMainCatId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "القسم الفرعي"),
                value: selectedSubCatId,
                items: snapshot.data!.docs.map((doc) {
                  return DropdownMenuItem(
                    value: doc.id,
                    onTap: () => selectedSubCatName = doc['name'], // حفظ الاسم
                    child: Text(doc['name']),
                  );
                }).toList(),
                onChanged: (val) => setState(() {
                  selectedSubCatId = val;
                  selectedProduct = null;
                  selectedUnit = null;
                }),
              );
            },
          ),

        // 3. اختيار المنتج
        if (selectedSubCatId != null)
          StreamBuilder<QuerySnapshot>(
            stream: (widget.firestore ?? FirebaseFirestore.instance).collection('products')
                .where('subId', isEqualTo: selectedSubCatId).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              return DropdownButtonFormField<Map<String, dynamic>>(
                decoration: const InputDecoration(labelText: "المنتج"),
                items: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: {...data, 'id': doc.id},
                    child: Text(data['name']),
                  );
                }).toList(),
                onChanged: (val) => setState(() {
                  selectedProduct = val;
                  selectedUnit = null;
                }),
              );
            },
          ),

        // 4. اختيار الوحدة
        if (selectedProduct != null && selectedProduct!['units'] != null)
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: "اختر الوحدة"),
            value: selectedUnit,
            items: (selectedProduct!['units'] as List).map((u) {
              return DropdownMenuItem<String>(value: u['unitName'], child: Text(u['unitName']));
            }).toList(),
            onChanged: (val) => setState(() => selectedUnit = val),
          ),

        if (selectedUnit != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: _priceController, decoration: const InputDecoration(labelText: "السعر"), keyboardType: TextInputType.number)),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _stockController, decoration: const InputDecoration(labelText: "الكمية المتاحة"), keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
            onPressed: () {
              if (_priceController.text.isNotEmpty && _stockController.text.isNotEmpty) {
                // تجميع البيانات في هيكل مطابق تماماً لطلبات الـ Web و Firestore
                widget.onProductAdded({
                  'productId': selectedProduct!['id'],
                  'productName': selectedProduct!['name'],
                  'mainCategoryId': selectedMainCatId,
                  'mainCategoryName': selectedMainCatName, // أضفنا الاسم هنا
                  'subCategoryId': selectedSubCatId,
                  'subCategoryName': selectedSubCatName, // أضفنا الاسم هنا
                  'imageUrl': selectedProduct!['imageUrl'] ?? '',
                  'units': [
                    {
                      'unitName': selectedUnit,
                      'price': double.tryParse(_priceController.text) ?? 0,
                      'availableStock': int.tryParse(_stockController.text) ?? 0,
                      'updatedAt': DateTime.now().toIso8601String(),
                    }
                  ],
                });

                _priceController.clear();
                _stockController.clear();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تمت الإضافة للقائمة")));
                setState(() { selectedUnit = null; });
              }
            },
            child: const Text("إضافة العرض", style: TextStyle(color: Colors.white)),
          )
        ],
      ],
    );
  }
}


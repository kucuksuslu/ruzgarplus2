import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerRegisterPage extends StatefulWidget {
  const CustomerRegisterPage({Key? key}) : super(key: key);

  @override
  State<CustomerRegisterPage> createState() => _CustomerRegisterPageState();
}

class _CustomerRegisterPageState extends State<CustomerRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final tcController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  DateTime? beginDate = DateTime.now();

  bool isLoading = false;
  String? errorMessage;
  String? successMessage;

  Future<int> _getNextUserId() async {
    // En büyük docID'yi bul (int olarak)
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get();

    int lastUserId = 0;
    if (snapshot.docs.isNotEmpty) {
      lastUserId = int.tryParse(snapshot.docs.first.id) ?? 0;
    }
    return lastUserId + 1;
  }

  Future<void> registerCustomer() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      successMessage = null;
    });

    final String name = nameController.text.trim();
    final String email = emailController.text.trim();
    final String tc = tcController.text.trim();
    final String phone = phoneController.text.trim();
    final String password = passwordController.text;

    try {
      // 1. Sıradaki user_id'yi al (docID olacak)
      final int newUserId = await _getNextUserId();

      // 2. Firebase Auth ile kullanıcı oluştur
      UserCredential credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;

      if (user != null) {
        // 3. Firestore'a kullanıcıyı kaydet (docID ve user_id aynı!)
        await FirebaseFirestore.instance.collection('users').doc(newUserId.toString()).set({
          'user_id': newUserId,
          'appcustomer_name': name,
          'appcustomer_email': email,
          'appcustomer_tc': tc,
          'app_phone': phone,
          'user_type': 'Aile',
          'parent_id': null,
          'created_at': FieldValue.serverTimestamp(),
          'begin_date': beginDate?.toIso8601String(),
          'firebase_uid': user.uid, // İstersen UID de saklayabilirsin
        });

        setState(() {
          isLoading = false;
          successMessage = "Kayıt başarılı!";
          errorMessage = null;
          _formKey.currentState?.reset();
        });
      } else {
        setState(() {
          isLoading = false;
          errorMessage = "Kayıt başarısız!";
          successMessage = null;
        });
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
        if (e.code == 'email-already-in-use') {
          errorMessage = "Bu e-posta adresi zaten kayıtlı.";
        } else if (e.code == 'weak-password') {
          errorMessage = "Şifreniz çok zayıf (en az 6 karakter olmalı).";
        } else if (e.code == 'invalid-email') {
          errorMessage = "Geçersiz e-posta adresi.";
        } else {
          errorMessage = "Kayıt başarısız: ${e.message}";
        }
        successMessage = null;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Bir hata oluştu: $e";
        successMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müşteri Kayıt'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (errorMessage != null) ...[
                Text(errorMessage!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              if (successMessage != null) ...[
                Text(successMessage!, style: const TextStyle(color: Colors.green)),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'İsim Soyisim'),
                validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
              ),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'E-posta'),
                validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                keyboardType: TextInputType.emailAddress,
              ),
              TextFormField(
                controller: tcController,
                decoration: const InputDecoration(labelText: 'TC Kimlik No'),
                validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
              ),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Telefon'),
                validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                keyboardType: TextInputType.phone,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Başlangıç Tarihi: ${beginDate != null ? beginDate!.toLocal().toString().split(' ')[0] : ''}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: beginDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => beginDate = picked);
                },
              ),
              TextFormField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Şifre'),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_add),
                label: Text(isLoading ? "Kaydediliyor..." : "Kaydet"),
                onPressed: isLoading
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          registerCustomer();
                        }
                      },
              )
            ],
          ),
        ),
      ),
    );
  }
}
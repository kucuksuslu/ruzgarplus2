import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Renk paleti
const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);

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
          'firebase_uid': user.uid,
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
      // Arkaplanda görsel
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/denemes.jpg"), // görsel yolunu buraya ekle
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          // gradient overlay (istenirse yumuşak bir renk efekti)
          decoration: const BoxDecoration(
          
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Center(
                child: Card(
                  elevation: 16,
                  color: Colors.white.withOpacity(0.95),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 38,
                            backgroundColor: kPrimaryPink.withOpacity(0.17),
                            child: const Icon(Icons.person_add, size: 42, color: Colors.black),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Müşteri Kayıt',
                            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.black),
                          ),
                          const SizedBox(height: 10),
                          if (errorMessage != null) ...[
                            Text(errorMessage!, style: TextStyle(color: kPrimaryPink, fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                          ],
                          if (successMessage != null) ...[
                            Text(successMessage!, style: TextStyle(color: kPrimaryPurple, fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                          ],
                          TextFormField(
                            controller: nameController,
                            decoration: InputDecoration(
                              labelText: 'İsim Soyisim',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.person, color: Colors.brown),
                              filled: true,
                              fillColor: kPrimaryPink.withOpacity(0.09),
                              labelStyle: const TextStyle(color: Colors.brown),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: emailController,
                            decoration: InputDecoration(
                              labelText: 'E-posta',
                              border: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.email, color: Colors.brown),
                              filled: true,
                              fillColor: kPrimaryPink.withOpacity(0.09),
                              labelStyle: const TextStyle(color: Colors.brown),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: tcController,
                            decoration: InputDecoration(
                              labelText: 'TC Kimlik No',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.credit_card, color: Colors.brown),
                              filled: true,
                              fillColor: kPrimaryPink.withOpacity(0.09),
                              labelStyle: const TextStyle(color: Colors.brown),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: phoneController,
                            decoration: InputDecoration(
                              labelText: 'Telefon',
                              border: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.phone, color: Colors.brown),
                              filled: true,
                              fillColor: kPrimaryPink.withOpacity(0.09),
                              labelStyle: const TextStyle(color: Colors.brown),
                            ),
                            validator: (v) => v == null || v.isEmpty ? 'Zorunlu alan' : null,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: passwordController,
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              focusedBorder: OutlineInputBorder(
                               borderRadius: BorderRadius.circular(78),
                                borderSide: const BorderSide(color: Colors.brown, width: 2),
                              ),
                              prefixIcon: const Icon(Icons.lock, color: Colors.brown),
                              filled: true,
                              fillColor: kPrimaryPink.withOpacity(0.09),
                              labelStyle: const TextStyle(color: Colors.brown),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              icon: isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ))
                                  : const Icon(Icons.person_add, color: Colors.white),
                              label: Text(isLoading ? "Kaydediliyor..." : "Kaydet"),
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      if (_formKey.currentState!.validate()) {
                                        registerCustomer();
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                elevation: 6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // GERİ DÖN BUTONU
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.arrow_back, color:  Colors.black),
                              label: const Text(
                                "Geri Dön",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                backgroundColor: kPrimaryPink.withOpacity(0.07),
                                foregroundColor: kPrimaryPink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
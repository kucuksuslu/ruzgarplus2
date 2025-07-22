import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Renkler
const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool isLoading = false;
  String message = '';
  Color messageColor = kPrimaryPurple;

  Future<void> _sendResetEmail() async {
    setState(() {
      isLoading = true;
      message = '';
    });

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        isLoading = false;
        message = "E-posta adresi gerekli.";
        messageColor = kPrimaryPink;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        isLoading = false;
        message = "Şifre sıfırlama e-postası gönderildi. Lütfen e-posta adresinizi kontrol edin.";
        messageColor = kPrimaryPurple;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
        if (e.code == 'user-not-found') {
          message = "Bu e-posta ile kayıtlı bir kullanıcı bulunamadı.";
        } else if (e.code == 'invalid-email') {
          message = "Geçersiz e-posta adresi.";
        } else {
          message = "Bir hata oluştu: ${e.message}";
        }
        messageColor = kPrimaryPink;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        message = "İşlem sırasında beklenmeyen bir hata oluştu: $e";
        messageColor = kPrimaryPink;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Arkaplan resmi
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('denemes.jpg'), // assets klasörüne eklemeyi unutma!
            fit: BoxFit.cover,
          ),
        ),
      child: SafeArea(
  child: Center(
    child: SingleChildScrollView(
      child: Card(
        elevation: 16,
        color: Colors.white.withOpacity(0.93),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // IKON - Arkaplanı siyah, kendisi beyaz
              CircleAvatar(
                radius: 42,
                backgroundColor: Colors.black,
                child: const Icon(Icons.lock_reset, size: 50, color: Colors.white),
              ),
              const SizedBox(height: 18),
              Text(
                "Şifre Sıfırlama",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "E-posta adresinizi girin, şifre sıfırlama bağlantısı e-posta ile gönderilecektir.",
                style: TextStyle(fontSize: 15, color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // INPUT: Kenarları kahverengi ve shadow
              Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.brown.withOpacity(0.23),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Colors.brown, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Colors.brown, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Colors.brown, width: 2.5),
                    ),
                    labelText: 'E-posta',
                    prefixIcon: const Icon(Icons.email, color: Colors.brown),
                    labelStyle: const TextStyle(color: Colors.brown),
                    filled: true,
                    fillColor: Colors.brown.withOpacity(0.05),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: messageColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 22),
              // E-POSTA GÖNDER: Siyah arka plan, beyaz yazı
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _sendResetEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ))
                      : const Text('E-posta Gönder'),
                ),
              ),
              const SizedBox(height: 12),
              // GİRİŞ EKRANINA DÖN: Kahverengi
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  "Giriş Ekranına Dön",
                  style: TextStyle(
                    color: Colors.brown,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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
    );
  }
}
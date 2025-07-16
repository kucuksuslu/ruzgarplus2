import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  bool isLoading = false;
  String message = '';
  Color messageColor = Colors.green;

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
        messageColor = Colors.red;
      });
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      setState(() {
        isLoading = false;
        message = "Şifre sıfırlama e-postası gönderildi. Lütfen e-posta adresinizi kontrol edin.";
        messageColor = Colors.green;
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
        messageColor = Colors.red;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        message = "İşlem sırasında beklenmeyen bir hata oluştu: $e";
        messageColor = Colors.red;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifremi Unuttum')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "E-posta adresinizi girin, şifre sıfırlama bağlantısı e-posta ile gönderilecektir.",
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-posta',
                prefixIcon: Icon(Icons.email),
              ),
            ),
            const SizedBox(height: 20),
            if (message.isNotEmpty)
              Text(
                message,
                style: TextStyle(color: messageColor, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _sendResetEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('E-posta Gönder'),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResetPasswordPage extends StatefulWidget {
  final String phone;
  const ResetPasswordPage({Key? key, required this.phone}) : super(key: key);

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String message = '';
  bool isLoading = false;
  bool showPass = false;

  Future<void> _resetPassword() async {
    setState(() {
      isLoading = true;
      message = '';
    });

    final code = _codeController.text.trim();
    final newPassword = _passwordController.text;
    if (code.isEmpty || newPassword.isEmpty) {
      setState(() {
        isLoading = false;
        message = "Tüm alanları doldurun.";
      });
      return;
    }
    if (newPassword.length > 7) {
      setState(() {
        isLoading = false;
        message = "Şifre en fazla 7 karakter olmalı!";
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("http://crm.ruzgarnet.site/api/reset-password-with-code"),
        headers: {
          'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'phone': widget.phone,
          'code': code,
          'new_password': newPassword,
        }),
      );

      final resp = jsonDecode(response.body);
      setState(() {
        isLoading = false;
        message = resp['message'] ?? '';
      });

      if (response.statusCode == 200 && resp['success'] == true) {
        // Başarılı, giriş ekranına yönlendir
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Şifre başarıyla değiştirildi!')),
        );
        Navigator.pop(context); // veya ana login sayfasına yönlendir
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        message = 'Hata oluştu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Şifre Oluştur')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Telefonunuza gelen kodu ve yeni şifrenizi girin.",
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'SMS Kodu',
                prefixIcon: Icon(Icons.sms),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: !showPass,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Yeni Şifre',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => showPass = !showPass),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (message.isNotEmpty)
              Text(
                message,
                style: TextStyle(color: message.contains("Hata") ? Colors.red : Colors.green),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Şifreyi Sıfırla'),
            ),
          ],
        ),
      ),
    );
  }
}
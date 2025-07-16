import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'login.dart'; // AnimatedLabelTextField sınıfını kullanmak için

class OtpRequestPage extends StatefulWidget {
  const OtpRequestPage({super.key});

  @override
  State<OtpRequestPage> createState() => _OtpRequestPageState();
}

class _OtpRequestPageState extends State<OtpRequestPage> {
  final TextEditingController _phoneController = TextEditingController();
  String _errorMessage = '';

 Future<void> _sendOtp() async {
  setState(() {
    _errorMessage = '';
  });

  final phone = _phoneController.text.trim();

  if (phone.isEmpty) {
    setState(() {
      _errorMessage = 'Lütfen telefon numaranızı girin.';
    });
    return;
  }

  final url = Uri.parse('http://crm.ruzgarnet.site/api/customercheck');

  try {
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode({'phone': phone}),
    );

    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}'); // <-- TÜM CEVABI KONSOLA BAS

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? 'Şifre gönderildi!')),
      );
    } else {
      final errorData = jsonDecode(response.body);
      setState(() {
        _errorMessage = errorData['message'] ?? 'Şifre gönderimi başarısız oldu.';
      });
      // Hata detayını konsolda göster
      print('HATA DETAYI: ${response.body}');
    }
  } catch (e) {
    setState(() {
      _errorMessage = 'Hata oluştu: $e';
    });
    print('EXCEPTION: $e');
  }
}

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
   return Scaffold(
  appBar: AppBar(
    title: const Text('Tek Kullanımlık Şifre Al'),
    backgroundColor: const Color(0xFFFF009D),
    centerTitle: true,
  ),
  body: SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24.0), // sadece sağ-sol padding
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20), // üstten biraz boşluk (isteğe göre ayarlayabilirsin)
        SizedBox(
          width: 180,
          height: 180,
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedLabelTextField(
          controller: _phoneController,
          label: 'Telefon Numaranız',
          icon: Icons.phone,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        if (_errorMessage.isNotEmpty)
          Text(
            _errorMessage,
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _sendOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontSize: 18),
          ),
          child: const Text('Şifre Gönder'),
        ),
      ],
    ),
  ),
);

  }
}

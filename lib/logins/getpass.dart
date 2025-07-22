import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
      print('Response Body: ${response.body}');

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
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 70),
            SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                'assets/densa.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 80),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 260,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.blue[700]!, // Hafif koyu mavi
                      width: 3.4,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 16, color: Colors.black),
                    decoration: const InputDecoration(
                      labelText: 'Telefon Numaranız',
                      labelStyle: TextStyle(
                        color: Colors.grey,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.phone, color: Colors.black45),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_errorMessage.isNotEmpty)
              Text(
                _errorMessage,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 50),
            Container(
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _sendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text('Şifre Gönder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
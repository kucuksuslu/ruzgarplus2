import 'package:http/http.dart' as http;
import 'dart:convert';

Future<List<dynamic>> fetchContents(String category) async {
  final response = await http.post(
    Uri.parse('http://crm.ruzgarnet.site/api/contents'),
    headers: {
      'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: jsonEncode({'category': category}),
  );

  print('Status Code: ${response.statusCode}');
  print('Response Body: ${response.body}');

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    // Eğer API'nin döndürdüğü data list değilse hata verebilir,
    // ona göre parse işlemi yap
    if (data is List) {
      return data;
    } else if (data is Map && data['data'] != null && data['data'] is List) {
      return data['data'];
    } else {
      throw Exception('Beklenmeyen veri formatı');
    }
  } else {
    // Burada dönen hata mesajını da yakala ve göster
    try {
      final errorData = jsonDecode(response.body);
      throw Exception('Hata ${response.statusCode}: ${errorData['message'] ?? response.body}');
    } catch (e) {
      throw Exception('Hata ${response.statusCode}: ${response.body}');
    }
  }
}

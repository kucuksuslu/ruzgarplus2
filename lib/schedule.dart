import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Set<int> shownNotificationIds = {};

Future<void> loadShownNotificationIds() async {
  final prefs = await SharedPreferences.getInstance();
  final List<String> shownIds = prefs.getStringList('shown_notification_ids') ?? [];
  shownNotificationIds = shownIds.map((e) => int.tryParse(e) ?? 0).toSet();
}

Future<void> saveShownNotificationIds() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('shown_notification_ids', shownNotificationIds.map((e) => e.toString()).toList());
}

Future<void> checkAndShowScheduledNotifications() async {
  print('[DEBUG] Bildirim kontrolü başlıyor...');
  await loadShownNotificationIds();

  final url = Uri.parse('http://crm.ruzgarnet.site/api/appnotis');

  try {
    print('[DEBUG] POST isteği hazırlanıyor (herkese bildirim).');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      // user_id yok, boş body gönderiyoruz
      body: json.encode({}),
    );

    print('[DEBUG] API yanıt kodu: ${response.statusCode}');
    print('[DEBUG] API yanıt gövdesi: ${response.body}');
    if (response.statusCode == 200) {
      final List<dynamic> notis = json.decode(response.body);
      print('[DEBUG] Gelen bildirim adedi: ${notis.length}');

      // Şu anki zamanı UTC olarak al
      final now = DateTime.now().toUtc();

      for (final noti in notis) {
        final int id = noti['id'];
        final String title = noti['title'] ?? 'Bildirim';
        final String body = noti['body'] ?? '';
        final String notifyTimeStr = noti['notify_time'];

        if (!shownNotificationIds.contains(id)) {
          // notify_time zaten UTC ISO formatında, UTC olarak parse edilir
          final DateTime notifyTime = DateTime.parse(notifyTimeStr).toUtc();

          // Gün aynı mı?
          bool sameDay = notifyTime.year == now.year &&
                         notifyTime.month == now.month &&
                         notifyTime.day == now.day;

          final Duration diff = notifyTime.difference(now);

          // Dakika farkı -1, 0, 1 ise bildirimi göster
          if (sameDay && diff.inMinutes.abs() <= 1) {
            print('[DEBUG] Bildirim son 2 dakikada! - id: $id, başlık: $title, notify_time: $notifyTime, now: $now');
            await _showLocalNotification(id, title, body);
            shownNotificationIds.add(id);
            await saveShownNotificationIds();
          } else {
            print('[DEBUG] Bildirim dakikası uyumsuz - id: $id, notify_time: $notifyTime, now: $now');
          }
        } else {
          print('[DEBUG] Bildirim zaten gösterilmiş (kalıcı hafıza) - id: $id');
        }
      }
    } else {
      print('Bildirimler alınamadı: ${response.statusCode}');
    }
  } catch (e, stack) {
    print('Bildirim sorgusu hatası: $e');
    print('Stack trace: $stack');
  }
}

Future<void> _showLocalNotification(int id, String title, String body) async {
  print('[DEBUG] Yerel bildirim gösteriliyor - id: $id, başlık: $title');
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'scheduled_channel',
    'Zamanlı Bildirimler',
    channelDescription: 'Zamanı gelen bildirimi gösterir',
    importance: Importance.max,
    priority: Priority.high,
    ongoing: false,       // SWIPE İLE SİLİNEBİLMESİ İÇİN
    autoCancel: true,     // Bildirim panelinden kaybolabilmesi için
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    platformChannelSpecifics,
    payload: 'scheduled_payload',
  );
  print('[DEBUG] Yerel bildirim gösterildi - id: $id');
}
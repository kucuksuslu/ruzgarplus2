import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

const String serverIp = "192.168.1.196";
const String wifiStatusEndpoint = "http://$serverIp:8000/api/fcm-pong";
const String sendAlertEndpoint = "http://$serverIp:8000/api/send-alert";

var _beautyEnvStarted = false;
String? _lastActiveRoomID;

const MethodChannel _agoraChannel = MethodChannel('com.example.ruzgarplus/agora_service');
const String agoraAppId = "8109382d3cde4ef881a8fb846237f2ed";
const String notificationSmallIcon = 'ic_stat_notify';

Future<void> initializeNotificationPlugin() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings(notificationSmallIcon);
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await FlutterLocalNotificationsPlugin().initialize(initializationSettings);
}

Future<void> ensureNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'background_channel',
    'Arka Plan Bildirimleri',
    description: 'Arka planda örnek bildirim',
    importance: Importance.max,
    playSound: true,
  );
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

Future<void> sendSimpleNotification() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'background_channel',
    'Arka Plan Bildirimleri',
    channelDescription: 'Arka planda çalışan örnek bildirim',
    importance: Importance.high,
    priority: Priority.high,
    ticker: 'ticker',
    icon: notificationSmallIcon,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    0,
    'Rüzgar Plus',
    'Bu bir arka plan örnek bildirimi!',
    platformChannelSpecifics,
    payload: 'background_payload',
  );
}

String guessAppName(String packageName) {
  final parts = packageName.split('.');
  if (parts.length >= 2) {
    String last = parts.last;
    if (last.length < 3) last = parts[parts.length - 2];
    return last.isNotEmpty
        ? (last[0].toUpperCase() + last.substring(1))
        : packageName;
  }
  return packageName;
}

Map<String, int> usageMsToHourMin(int ms) {
  int totalMinutes = (ms / 1000 / 60).floor();
  int hours = totalMinutes ~/ 60;
  int minutes = totalMinutes % 60;
  return {'hours': hours, 'minutes': minutes};
}

Future<void> showAlarmNotification(String? title, String? body) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'background_channel',
    'Arka Plan Bildirimleri',
    channelDescription: 'Acil alarm bildirimi',
    importance: Importance.max,
    priority: Priority.high,
    sound: RawResourceAndroidNotificationSound('alarm'),
    ticker: 'ticker',
    icon: notificationSmallIcon,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    1,
    title ?? 'Acil Durum!',
    body ?? 'Acil durum bildirimi geldi!',
    platformChannelSpecifics,
    payload: 'alarm_payload',
  );
}

Future<void> showLocalNotification(String title, String body) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'background_channel',
    'Arka Plan Bildirimleri',
    channelDescription: 'Acil alarm bildirimi',
    importance: Importance.max,
    priority: Priority.high,
    ticker: 'ticker',
    icon: notificationSmallIcon,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.show(
    2,
    title,
    body,
    platformChannelSpecifics,
    payload: 'area_alert_payload',
  );
}

Future<void> playAlarmSoundTwice() async {
  final player = AudioPlayer();
  print('[DEBUG] [ALARM] Alarm sesi başlatılıyor (2 defa çalacak)...');
  for (int i = 0; i < 2; i++) {
    await player.play(AssetSource('alarm.mp3'), volume: 1.0, mode: PlayerMode.lowLatency);
    await Future.delayed(const Duration(milliseconds: 1200));
  }
  await player.dispose();
  print('[DEBUG] [ALARM] Alarm sesi çalma işlemi bitti.');
}

Future<void> showBigPictureNotification(
    String? title, String? body, String? imageUrl) async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final sound = RawResourceAndroidNotificationSound('noti');

  if (imageUrl != null && imageUrl.isNotEmpty) {
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      final String filePath = '${directory.path}/notification_image.jpg';
      final response = await http.get(Uri.parse(imageUrl));
      final File file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      final BigPictureStyleInformation bigPictureStyleInformation =
          BigPictureStyleInformation(
        FilePathAndroidBitmap(filePath),
        contentTitle: title,
        summaryText: body,
      );

      final AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'background_channel',
        'Arka Plan Bildirimleri',
        channelDescription: 'Arka planda örnek bildirim',
        styleInformation: bigPictureStyleInformation,
        importance: Importance.max,
        priority: Priority.high,
        sound: sound,
        ticker: 'ticker',
        icon: notificationSmallIcon,
      );

      final NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.show(
        0,
        title ?? '',
        body ?? '',
        platformChannelSpecifics,
        payload: 'background_payload',
      );
    } catch (e) {
      print('[DEBUG] Resimli bildirim gösterilemedi: $e');
    }
  } else {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'background_channel',
      'Arka Plan Bildirimleri',
      channelDescription: 'Arka planda örnek bildirim',
      importance: Importance.max,
      priority: Priority.high,
      sound: sound,
      ticker: 'ticker',
      icon: notificationSmallIcon,
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      title ?? '',
      body ?? '',
      platformChannelSpecifics,
      payload: 'background_payload',
    );
  }
}

Future<void> logMostUsedApps(int userId, int? parentId) async {
  try {
    debugPrint("[logMostUsedApps] Called for userId=$userId, parentId=$parentId");
    DateTime end = DateTime.now();
    DateTime start = end.subtract(const Duration(days: 1));
    debugPrint("[logMostUsedApps] Query stats from $start to $end");

    List<UsageInfo> usageStats = await UsageStats.queryUsageStats(start, end);
    debugPrint("[logMostUsedApps] Usage stats count: ${usageStats.length}");

    final prefs = await SharedPreferences.getInstance();
    final String? appCustomerName = prefs.getString('appcustomer_name');
    debugPrint("[logMostUsedApps] appCustomerName: $appCustomerName");

    Map<String, Map<String, int>> stats = {};
    for (var info in usageStats) {
      dynamic value = info.totalTimeInForeground ?? 0;

      int ms;
      if (value is int) {
        ms = value;
      } else if (value is double) {
        ms = value.toInt();
      } else if (value is String) {
        ms = int.tryParse(value) ?? 0;
      } else if (value is num) {
        ms = value.toInt();
      } else {
        ms = 0;
      }

      if (ms == 0) continue;

      final appName = guessAppName(info.packageName ?? "");
      final hourMin = usageMsToHourMin(ms);
      stats[appName] = hourMin;
      debugPrint(
        "[logMostUsedApps] App: $appName, Foreground(ms): $ms, HourMin: $hourMin",
      );
    }
    String docId = "$userId";
    final docRef = FirebaseFirestore.instance.collection('user_usagestats').doc(docId);

    if (stats.isNotEmpty) {
      debugPrint("[logMostUsedApps] Writing to user_usagestats/$docId: ${stats.length} apps");
      await docRef.set({
        'user_id': userId,
        'parent_id': parentId,
        'stats': stats,
        'appcustomer_name': appCustomerName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'user_id': userId,
        'parent_id': parentId,
        'timestamp': FieldValue.serverTimestamp(),
        'note': "En çok kullanılan uygulamalar (flutter usage_stats) user_usagestats'a kaydedildi.",
        'apps_count': stats.length,
      });
      debugPrint("[logMostUsedApps] Firestore kayıtları tamamlandı.");
    } else {
      debugPrint("[logMostUsedApps] No usage stats found, nothing written.");
    }
  } catch (e, stack) {
    debugPrint("[logMostUsedApps] ERROR: $e\n$stack");
  }
}

Future<void> logInternetStatusWithHttp(int userId) async {
  bool isConnected = false;
  int statusCode = -1;
  try {
    final response = await http.get(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 5));
    statusCode = response.statusCode;
    isConnected = statusCode == 200;
  } catch (e) {
    isConnected = false;
  }
  try {
    final logsCollection = FirebaseFirestore.instance.collection('internet_status_logs');
    final docId = "$userId";
    await logsCollection.doc(docId).set({
      'user_id': userId.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'is_connected': isConnected,
      'http_status_code': statusCode,
    }, SetOptions(merge: true));
  } catch (e) {
    final logsCollection = FirebaseFirestore.instance.collection('internet_status_logs');
    final docId = "$userId";
    await logsCollection.doc(docId).set({
      'user_id': userId.toString(),
      'timestamp': FieldValue.serverTimestamp(),
      'is_connected': false,
      'http_status_code': statusCode,
      'error': e.toString(),
    }, SetOptions(merge: true));
  }
}

Future<bool> ensureLocationPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return false;
    }
  }
  if (permission == LocationPermission.deniedForever) {
    return false;
  }
  return true;
}

Future<void> updateChildLocationHistory(
  int userId,
  double lat,
  double lng,
  String? appCustomerName,
  String? userType,
  int? parentId,
) async {
  if (userType == 'Aile') {
    return;
  }
  final docRef = FirebaseFirestore.instance
      .collection('user_locations_history')
      .doc(userId.toString());

  final now = DateTime.now();
  final currentLocation = {
    'lat': lat,
    'lng': lng,
    'timestamp': now.toIso8601String(),
    'appcustomer_name': appCustomerName,
    'user_id': userId,
    'parent_id': parentId,
  };

  final doc = await docRef.get();
  List<dynamic> locations = [];
  if (doc.exists && doc.data() != null && doc.data()!.containsKey('locations')) {
    locations = List.from(doc.data()!['locations']);
  }
  locations.add(currentLocation);
  if (locations.length > 3) {
    locations = locations.sublist(locations.length - 3);
  }

  await docRef.set({
    'locations': locations,
    'parent_id': parentId,
    'user_id': userId,
    'appcustomer_name': appCustomerName,
  }, SetOptions(merge: true));
}

Future<void> logLocationToFirestore(int userId) async {
  try {
    bool hasPermission = await ensureLocationPermission();
    if (!hasPermission) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final int? parentId = prefs.getInt('parent_id');
    final String? userType = prefs.getString('user_type');
    final String? appCustomerName = prefs.getString('appcustomer_name');
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    double lat = position.latitude;
    double lon = position.longitude;
    final docId = "$userId";
    await FirebaseFirestore.instance.collection('user_locations').doc(docId).set({
      'user_id': userId.toString(),
      'parent_id': parentId,
      'latitude': lat,
      'appcustomer_name': appCustomerName,
      'user_type':userType,
      'longitude': lon,
      'timestamp': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await updateChildLocationHistory(userId, lat, lon, appCustomerName, userType, parentId);
  } catch (e, stack) {}
}

Future<void> setUserOfflineOnTerminate() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return;

    final docId = "$userId";
    await FirebaseFirestore.instance
        .collection('live_users')
        .doc(docId)
        .set({'online': false}, SetOptions(merge: true));
  } catch (e) {}
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000;
  final double phi1 = lat1 * pi / 180;
  final double phi2 = lat2 * pi / 180;
  final double deltaPhi = (lat2 - lat1) * pi / 180;
  final double deltaLambda = (lon2 - lon1) * pi / 180;
  final double a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
      cos(phi1) * cos(phi2) *
          sin(deltaLambda / 2) * sin(deltaLambda / 2);
  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  final double d = R * c;
  return d;
}

Future<void> checkChildrenAreaAlerts(int userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    String? userType = prefs.getString('user_type');
    if (userType != 'Aile') return;

    final childrenQuery = await FirebaseFirestore.instance
        .collection('user_locations')
        .where('parent_id', isEqualTo: userId)
        .where('user_type', isEqualTo: 'Çocuk')
        .get();

    if (childrenQuery.docs.isEmpty) {
      return;
    }

    final areaLimitDoc = await FirebaseFirestore.instance
        .collection('area_limits')
        .doc(userId.toString())
        .get();

    if (!areaLimitDoc.exists) {
      return;
    }
    final areaData = areaLimitDoc.data()!;
    final double centerLat = (areaData['center_lat'] as num).toDouble();
    final double centerLng = (areaData['center_lng'] as num).toDouble();
    final double radiusM = (areaData['radius_m'] as num).toDouble();

    List<String> outsideNames = [];
    for (var doc in childrenQuery.docs) {
      final data = doc.data();
      final double lat = (data['latitude'] as num).toDouble();
      final double lng = (data['longitude'] as num).toDouble();
      final String name = data['appcustomer_name'] ?? 'Bilinmeyen';
      final double distance = calculateDistance(lat, lng, centerLat, centerLng);
      if (distance > radiusM) {
        outsideNames.add(name);
      }
    }

    if (outsideNames.isNotEmpty) {
      final String msg = "Alan dışında olan çocuk(lar): ${outsideNames.join(', ')}";
      await showLocalNotification("Uyarı", msg);
    }
  } catch (e, stack) {}
}

Future<void> handleInternetTestMessage(RemoteMessage message) async {
  if (message.data['type'] == 'internet_test') {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.get('user_id')?.toString() ?? '';
    final String testId = message.data['test_id'] ?? '';

    if (userId.isNotEmpty && testId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('internet_status_logs').add({
        'user_id': userId,
        'is_connected': true,
        'timestamp': FieldValue.serverTimestamp(),
        'test_id': testId,
      });

      // Gelişmiş log tutmak istiyorsan (opsiyonel)
      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][INTERNET_TEST][PONG] internet_status_logs kaydedildi',
        'user_id': userId,
        'test_id': testId,
      });
    }
  }
}

Future<void> handlePingPong(RemoteMessage message, {required String userId, required bool isBackground}) async {
  final bool isPing = (message.data['type'] == 'ping' || message.data['ping'] == '1');
  final String requestId = message.data['requestId'] ?? message.data['request_id'] ?? '';

  await FirebaseFirestore.instance.collection('flutter_background_logs').add({
    'timestamp': FieldValue.serverTimestamp(),
    'note': '[DEBUG][PONG] Handler çağrıldı',
    'isPing': isPing,
    'requestId': requestId,
    'userId': userId,
    'handler': isBackground ? 'background' : 'foreground',
    'messageData': message.data,
  });

  if (isPing && userId.isNotEmpty) {
    try {
      final response = await http.post(
        Uri.parse(wifiStatusEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'requestId': requestId,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][PONG] POST atıldı',
        'http_status': response.statusCode,
        'http_body': response.body,
        'userId': userId,
        'requestId': requestId,
        'handler': isBackground ? 'background' : 'foreground',
      });

      if (response.statusCode != 200) {
        await FirebaseFirestore.instance.collection('flutter_background_logs').add({
          'timestamp': FieldValue.serverTimestamp(),
          'note': 'wifi-status API HATASI (FCM PONG)',
          'http_status': response.statusCode,
          'http_body': response.body,
          'user_id': userId,
          'requestId': requestId,
          'handler': isBackground ? 'background' : 'foreground',
        });
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({
            'last_online': FieldValue.serverTimestamp(),
            'last_pong_request_id': requestId,
          }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][PONG] Firestore güncellendi',
        'userId': userId,
        'requestId': requestId,
        'handler': isBackground ? 'background' : 'foreground',
      });
    } catch (e, stack) {
      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': 'wifi-status API Exception (FCM PONG)',
        'error': e.toString(),
        'stack': stack.toString(),
        'user_id': userId,
        'requestId': requestId,
        'handler': isBackground ? 'background' : 'foreground',
      });
    }
  } else {
    await FirebaseFirestore.instance.collection('flutter_background_logs').add({
      'timestamp': FieldValue.serverTimestamp(),
      'note': '[DEBUG][PONG] Ping mesajı değil veya userId yok, istek atılmadı.',
      'userId': userId,
      'requestId': requestId,
      'isPing': isPing,
      'handler': isBackground ? 'background' : 'foreground',
    });
  }
}

void setupForegroundFCMHandler() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id')?.toString() ?? '';
    await handlePingPong(message, userId: userId, isBackground: false);
    await handleInternetTestMessage(message);

    // Bildirimi notification alanıyla geldiyse, local olarak da göster (uygulama ön planda ise)
    if (message.notification != null) {
      await showLocalNotification(
        message.notification!.title ?? 'Rüzgar Plus',
        message.notification!.body ?? ''
      );
    }

    if (message.data['type'] == 'agora_start') {
      final String roomId = message.data['roomId'] ?? '';
      final String role = message.data['role'] ?? '';
      final String otherUserId = message.data['otherUserId'] ?? '';
      // Sadece doğru kullanıcıda başlat
      return;
    }

    if (message.data['type'] == 'chat') {
      print('[DEBUG][FCM][FOREGROUND] chat tipinde mesaj bildirimi alındı.');
      await showLocalNotification(
        message.data['sender_name'] ?? 'Yeni Mesaj',
        message.data['text'] ?? '',
      );
      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][FCM][FOREGROUND] chat tipi local notification gösterildi',
        'data': message.data,
        'user_id': userId,
      });
      return;
    }

    if (message.data['type'] == 'alarm') {
      await showAlarmNotification(
        message.notification?.title ?? message.data['title'] ?? 'Acil Durum!',
        message.notification?.body ?? message.data['body'] ?? 'Acil durum bildirimi geldi!',
      );
      await playAlarmSoundTwice();
      return;
    }

    final String? notificationType = message.data['notification_type'];
    final String? imageUrl = message.data['image'];
    final String? status = message.data['status'];
    final String? title  = message.data['title'];
    final String? isAppOpen  = message.data['is_app_open'];

    if (notificationType == 'app_open_status') {
      await showAppOpenStatusNotification(title, status, isAppOpen, imageUrl);
    } else if (notificationType == 'internet_status') {
      await showInternetStatusNotification(title, status, imageUrl);
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      await showBigPictureNotification(title, status, imageUrl);
    }
  });
}

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('user_id')?.toString() ?? '';

  await handlePingPong(message, userId: userId, isBackground: true);
  await handleInternetTestMessage(message);

  // Bildirimi notification alanıyla geldiyse, local olarak da göster (arka planda ise gösterilmesine gerek yok, sistem gösterir)
  // Ama bazı özel cihazlarda arka planda da local notification göstermek istersen şuraya ekleyebilirsin:
  // if (message.notification != null) {
  //   await showLocalNotification(
  //     message.notification!.title ?? 'Rüzgar Plus',
  //     message.notification!.body ?? ''
  //   );
  // }

  if (message.data['type'] == 'agora_start') {
    final String roomId = message.data['roomId'] ?? '';
    final String role = message.data['role'] ?? '';
    final String otherUserId = message.data['otherUserId'] ?? '';
    // Sadece doğru kullanıcıda başlat
    if (roomId.isNotEmpty && userId.isNotEmpty && otherUserId.isNotEmpty && userId == otherUserId) {
      try {
        const platform = MethodChannel('com.example.ruzgarplus/agora_service');
        await platform.invokeMethod('startAgoraService', {
          'roomId': roomId,
          'userId': userId,
          'otherUserId': otherUserId,
          'role': 'broadcaster',
        });
        print('[DEBUG][AGORA][FCM] AgoraForegroundService başlatıldı!');
      } catch (e) {
        print('[DEBUG][AGORA][FCM][ERROR] Service başlatılamadı: $e');
      }

      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][AGORA][BACKGROUND] Agora başlatıldı (broadcaster)',
        'roomId': roomId,
        'userId': userId,
        'role': 'broadcaster',
        'otherUserId': otherUserId,
        'message': message.data,
      });
    } else {
      await FirebaseFirestore.instance.collection('flutter_background_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'note': '[DEBUG][AGORA][BACKGROUND] Agora başlatılmadı, userId eşleşmedi',
        'roomId': roomId,
        'userId': userId,
        'role': role,
        'otherUserId': otherUserId,
        'message': message.data,
      });
    }
    return;
  }

  if (message.data['type'] == 'chat') {
    await showLocalNotification(
      message.data['sender_name'] ?? 'Yeni Mesaj',
      message.data['text'] ?? '',
    );
    await FirebaseFirestore.instance.collection('flutter_background_logs').add({
      'timestamp': FieldValue.serverTimestamp(),
      'note': '[DEBUG][FCM][BACKGROUND] chat tipi local notification gösterildi',
      'data': message.data,
      'user_id': userId,
    });
    return;
  }

  if (message.data['type'] == 'alarm') {
    await showAlarmNotification(
      message.notification?.title ?? message.data['title'] ?? 'Acil Durum!',
      message.notification?.body ?? message.data['body'] ?? 'Acil durum bildirimi geldi!',
    );
    await playAlarmSoundTwice();
    return;
  }

  final String? notificationType = message.data['notification_type'];
  final String? imageUrl = message.data['image'];
  final String? status = message.data['status'];
  final String? title  = message.data['title'];
  final String? isAppOpen  = message.data['is_app_open'];

  if (notificationType == 'app_open_status') {
    await showAppOpenStatusNotification(title, status, isAppOpen, imageUrl);
  } else if (notificationType == 'internet_status') {
    await showInternetStatusNotification(title, status, imageUrl);
  } else if (imageUrl != null && imageUrl.isNotEmpty) {
    await showBigPictureNotification(title, status, imageUrl);
  }
}

Future<void> showAppOpenStatusNotification(
    String? title, String? status, String? isAppOpen, String? imageUrl) async {
  String body = (status ?? '') +
      (isAppOpen != null ? "\nUygulama: " + (isAppOpen == "true" ? "Açık" : "Kapalı") : '');
  await showBigPictureNotification(title, body, imageUrl);
}

Future<void> showInternetStatusNotification(
    String? title, String? status, String? imageUrl) async {
  await showBigPictureNotification(title, status, imageUrl);
}

void listenBroadcastRoomsForSelf() async {
  print('[DEBUG] listenBroadcastRoomsForSelf() çağrıldı');
  final prefs = await SharedPreferences.getInstance();
  final myUserId = prefs.getInt('user_id')?.toString();
  print('[DEBUG] SharedPreferences\'ten user_id alındı: $myUserId');
  if (myUserId == null) {
    print('[DEBUG][ERROR] user_id bulunamadı, dinleme başlatılmadı!');
    return;
  }

  print('[DEBUG] Firestore subscription başlatılıyor: otherUserId == $myUserId && status == active');
  final myUserIdStr = myUserId.toString();
  print('[DEBUG] user_id string: $myUserIdStr');
  FirebaseFirestore.instance
      .collection('active_audio_rooms')
      .where('otherUserId', isEqualTo: myUserIdStr)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .listen((snapshot) async {
    print('[DEBUG][SNAPSHOT] Yeni snapshot geldi. Toplam oda: ${snapshot.docs.length}');
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final roomId = data['roomID'] ?? doc.id;
      final userID = data['userID']?.toString() ?? '';
      final status = data['status'] ?? '';
      final otherUserId = data['otherUserId']?.toString() ?? '';

      print('[DEBUG][SNAPSHOT] Oda bulundu: roomId=$roomId, userID=$userID, status=$status, otherUserId=$otherUserId, myUserId=$myUserId');

      if (status == 'active') {
        print('[DEBUG][MATCH] status=active, oda başlatılıyor...');
        try {
          await _agoraChannel.invokeMethod('startAgoraListening', {
            "roomId": roomId,
            "userId": myUserId,
            "role": "broadcaster",  // veya ihtiyaca göre "audience"
            "otherUserId": userID,
          });
          print('[DEBUG][AGORA] startAgoraListening başarılı!');
          await FirebaseFirestore.instance.collection('flutter_background_logs').add({
            'timestamp': FieldValue.serverTimestamp(),
            'note': '[DEBUG][AGORA][AUTO_BROADCAST] Oda match, broadcaster başlatıldı',
            'roomId': roomId,
            'myUserId': myUserId,
            'userID': userID,
          });
        } catch (e, st) {
          print('[DEBUG][AGORA][ERROR] startAgoraListening başarısız: $e');
          await FirebaseFirestore.instance.collection('flutter_background_logs').add({
            'timestamp': FieldValue.serverTimestamp(),
            'note': '[DEBUG][AGORA][AUTO_BROADCAST][ERROR] Başlatılamadı',
            'roomId': roomId,
            'error': e.toString(),
            'myUserId': myUserId,
            'userID': userID,
          });
        }
      } else {
        print('[DEBUG][SKIP] Oda aktif değil, atlandı.');
      }
    }
  }, onError: (e) {
    print('[DEBUG][SNAPSHOT][ERROR] Dinlemede hata: $e');
  });
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Foreground Service'i başlat!
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    await service.setForegroundNotificationInfo(
      title: "Rüzgar Plus arka planda çalışıyor",
      content: "Kullanım ve konum verileri kaydediliyor.",
    );
    print("[DEBUG] Android foreground service başlatıldı.");
  }

  await initializeNotificationPlugin();
  await ensureNotificationChannel();

  listenBroadcastRoomsForSelf();
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);
  setupForegroundFCMHandler();

  Timer.periodic(const Duration(minutes: 2), (_) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    int? parentId = prefs.getInt('parent_id');
    if (userId != null) {
      await logMostUsedApps(userId, parentId);
      await logLocationToFirestore(userId);
      await checkChildrenAreaAlerts(userId);
    }
  });

  service.on('onDestroy').listen((event) async {
    await setUserOfflineOnTerminate();
  });

  service.on('onTaskRemoved').listen((event) async {
    await setUserOfflineOnTerminate();
  });
}
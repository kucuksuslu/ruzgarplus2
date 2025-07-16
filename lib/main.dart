import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ruzgarplus/logins/login.dart';
import 'package:ruzgarplus/logins/loginhome.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Arka planda (veya uygulama kapalıyken) gelen bildirimleri yakalamak için:
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Arka planda bildirim: ${message.notification?.title} - ${message.notification?.body}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print("Firebase başlatıldı!");
  } catch (e, stack) {
    print("Firebase başlatılırken hata: $e\n$stack");
  }

  // Gerekli izinleri iste
  await _requestPermissions();

  // Background handler'ı tanımla
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  await [
    Permission.location,
    Permission.notification, // Bildirim için
    Permission.microphone,   // <-- bunu ekle
    // Eğer başka izinler gerekiyorsa buraya ekle
  ].request();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rüzgar Plus',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      navigatorObservers: [routeObserver],
      home: const loginHome(),
    );
  }
}
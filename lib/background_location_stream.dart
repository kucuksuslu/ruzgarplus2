import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LatLng {
  final double latitude;
  final double longitude;
  LatLng(this.latitude, this.longitude);
}

Future<void> startBackgroundLocationStream() async {
  print('[DEBUG] startBackgroundLocationStream() başlatıldı');
  final firestore = FirebaseFirestore.instance;
  final prefs = await SharedPreferences.getInstance();

  final userId = prefs.getInt('user_id');
  final userFilter = prefs.getString('user_filter') ?? 'Aile';
  final authToken = prefs.getString('auth_token');

  print('[DEBUG] userId: $userId, userFilter: $userFilter, authToken: $authToken');

  if (userId == null || authToken == null) {
    print('[DEBUG] userId veya authToken NULL, fonksiyondan çıkılıyor');
    return;
  }

  // Alan limiti Firestore'dan oku
  LatLng? selectedAreaCenter;
  double? selectedAreaRadiusMeter;
  bool alarmActive = false;

  print('[DEBUG] Alan limiti Firestore’dan okunuyor...');
  final areaLimitDoc = await firestore.collection('area_limits').doc(userId.toString()).get();
  if (areaLimitDoc.exists && areaLimitDoc.data() != null) {
    final data = areaLimitDoc.data()!;
    selectedAreaCenter = LatLng(data['center_lat'], data['center_lng']);
    selectedAreaRadiusMeter = (data['radius_m'] as num).toDouble();
    alarmActive = true;
    print('[DEBUG] Alan limiti bulundu: center=($selectedAreaCenter), radius=$selectedAreaRadiusMeter, alarmActive=$alarmActive');
  } else {
    print('[DEBUG] Alan limiti bulunamadı.');
  }

  Position? lastKnownPosition;
  const movementThresholdMeters = 2.0;

  print('[DEBUG] Konum streami başlatılıyor...');
  Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    ),
  ).listen((Position? position) async {
    print('[DEBUG] Yeni pozisyon geldi: $position');
    if (position == null) {
      print('[DEBUG] Pozisyon NULL, kaydetmiyorum.');
      return;
    }

    if (lastKnownPosition != null) {
      double distance = Geolocator.distanceBetween(
        lastKnownPosition!.latitude,
        lastKnownPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      print('[DEBUG] Son konumdan mesafe: $distance metre');
      if (distance < movementThresholdMeters) {
        print('[DEBUG] Hareket eşiği aşılmadı ($distance<$movementThresholdMeters), kaydedilmiyor.');
        return;
      }
    }
    lastKnownPosition = position;

    // Alan dışı kontrolü (isteğe bağlı)
    if (alarmActive && selectedAreaCenter != null && selectedAreaRadiusMeter != null) {
      double distance = Geolocator.distanceBetween(
        selectedAreaCenter.latitude,
        selectedAreaCenter.longitude,
        position.latitude,
        position.longitude,
      );
      print('[DEBUG] Alan merkezine mesafe: $distance, sınır: $selectedAreaRadiusMeter');
      if (distance > selectedAreaRadiusMeter) {
        print('[BG] Alan dışında! Bildirim tetiklenmeli.');
      } else {
        print('[DEBUG] Kullanıcı alan içinde.');
      }
    }

    // Firestore'a konumu kaydet (sadece "Aile" değilse)
    if (userFilter != "Aile") {
      final documentIdToSave = '${userId}_${userFilter}';
      print('[DEBUG] Firestore\'a kaydediliyor: doc=$documentIdToSave, lat=${position.latitude}, lng=${position.longitude}');
      try {
     
        print('[BG] Konum Firestore\'a kaydedildi: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('[ERROR] Firestore\'a kaydederken hata: $e');
      }
    } else {
      print('[DEBUG] userFilter "Aile", konum Firestore\'a kaydedilmiyor.');
    }
  }, onError: (e) {
    print('[ERROR] Konum streaminde hata: $e');
  });
}
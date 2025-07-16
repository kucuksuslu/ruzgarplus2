import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RestrictedWatchdog {
  static const platform = MethodChannel('barisceliker/appswitch');

  /// restrictedApps: ["com.instagram.android", "com.whatsapp", ...]
  static Future<void> startWatchdog(
      List<String> restrictedApps, BuildContext context) async {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final String? packageName =
            await platform.invokeMethod<String>('getActiveApp');
        debugPrint("DEBUG: Aktif uygulama: $packageName");
        if (packageName != null && restrictedApps.contains(packageName)) {
          debugPrint("DEBUG: Restricted app açıldı, uygulamadan atılıyor!");
          timer.cancel();
          // Çıkış:
          if (context.mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            // veya: SystemNavigator.pop();
          }
        }
      } catch (e) {
        debugPrint("DEBUG: getActiveApp hata: $e");
      }
    });
  }
}
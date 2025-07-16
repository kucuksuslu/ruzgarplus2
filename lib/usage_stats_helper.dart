import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UsageStatsHelper {
  static const usageStatsResult = "com.example.ruzgarplus.USAGE_STATS_RESULT";

  static Future<void> startNativeUsageStatsService() async {
    const platform = MethodChannel('com.example.ruzgarplus/native');
    try {
      await platform.invokeMethod('startUsageStatsService');
    } catch (e) {
      debugPrint("Servis başlatılamadı: $e");
    }
  }
}
import 'package:flutter/services.dart';

class UsageStatsPlugin {
  static const MethodChannel _channel = MethodChannel('com.example.app/usage_stats');

  static Future<dynamic> getUsageStats() async {
    return await _channel.invokeMethod('getUsageStats');
  }
}
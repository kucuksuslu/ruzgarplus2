import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

// RENKLER
const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);
const Color kProfileBg = Color(0xFFF6F2FB);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _channel = MethodChannel('com.example.ruzgarplus/accessibility');
  String? lastDetectedApp;

  int? _userId;
  int? _parentId;
  String? _userType;
  String? _userName;

  List<Map<String, dynamic>> _relatedUsers = [];
  StreamSubscription<QuerySnapshot>? _usersSub;

  Map<String, Map<String, dynamic>> _internetStatusDocs = {};
  StreamSubscription<QuerySnapshot>? _internetStatusSub;

  late BuildContext pageContext;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeMessage);
    _loadUserInfoAndListenUsers();
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _internetStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _handleNativeMessage(MethodCall call) async {
    if (call.method == 'onAppDetected') {
      setState(() {
        lastDetectedApp = call.arguments?.toString();
      });
      debugPrint('Algılanan uygulama (native): ${call.arguments}');
    }
  }

  Future<void> _loadUserInfoAndListenUsers() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('user_id');
    _parentId = prefs.getInt('parent_id');
    _userType = prefs.getString('user_type');
    _userName = prefs.getString('appcustomer_name');
    setState(() {});
    _listenRelatedUsers();
  }

  void _listenRelatedUsers() {
    final firestore = FirebaseFirestore.instance;
    if (_userType == "Aile" && _userId != null) {
      _usersSub?.cancel();
      _usersSub = firestore
          .collection('users')
          .where('parent_id', isEqualTo: _userId)
          .snapshots()
          .listen((snapshot) async {
        List<Map<String, dynamic>> users = [];
        final ownDoc = await firestore.collection('users').doc(_userId.toString()).get();
        if (ownDoc.exists) {
          var map = ownDoc.data()!;
          map['id'] = ownDoc.id;
          users.add(map);
        }
        for (var doc in snapshot.docs) {
          var map = doc.data();
          map['id'] = doc.id;
          users.add(map);
        }
        setState(() {
          _relatedUsers = users;
        });
        _listenInternetStatuses();
      });
    } else if (_userType == "Cocuk" && _parentId != null && _userId != null) {
      _usersSub?.cancel();
      _usersSub = FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: [
            _userId.toString(),
            _parentId.toString()
          ])
          .snapshots()
          .listen((snapshot) {
        List<Map<String, dynamic>> users = [];
        for (var doc in snapshot.docs) {
          var map = doc.data();
          map['id'] = doc.id;
          users.add(map);
        }
        setState(() {
          _relatedUsers = users;
        });
        _listenInternetStatuses();
      });
    }
  }

  void _listenInternetStatuses() {
    final firestore = FirebaseFirestore.instance;
    List<String> userIds = _relatedUsers.map((e) => e['id'].toString()).toList();
    if (userIds.isEmpty) return;

    _internetStatusSub?.cancel();
    _internetStatusSub = firestore
        .collection('internet_status_logs')
        .where('parent_id', whereIn: userIds)
        .snapshots()
        .listen((snapshot) {
      Map<String, Map<String, dynamic>> lastDocs = {};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final userIdStr = data['user_id'].toString();
        final ts = data['timestamp'];
        if (userIdStr.isEmpty) continue;
        if (!lastDocs.containsKey(userIdStr) ||
            _getTimestamp(ts).isAfter(
              _getTimestamp(lastDocs[userIdStr]?['timestamp'])
            )) {
          lastDocs[userIdStr] = data;
        }
      }
      setState(() {
        _internetStatusDocs = lastDocs;
      });
    });
  }

  DateTime _getTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is Map && ts.containsKey('_seconds')) {
      return DateTime.fromMillisecondsSinceEpoch(ts['_seconds'] * 1000);
    }
    if (ts is DateTime) return ts;
    return DateTime.now();
  }

  void openAccessibilitySettings() {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.ACCESSIBILITY_SETTINGS',
      );
      intent.launch();
    } catch (_) {}
  }

  Future<void> openUsageAccessSettings() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.settings.USAGE_ACCESS_SETTINGS',
      );
      await intent.launch();
    } catch (_) {}
  }

  Future<void> checkAndRequestOverlayPermission() async {
    if (!Platform.isAndroid) return;

    const overlayChannel = MethodChannel('com.example.ruzgarplus/overlay');
    bool? hasPermission;
    try {
      hasPermission = await overlayChannel.invokeMethod<bool>('checkOverlayPermission');
    } on PlatformException {
      hasPermission = false;
    }

    if (hasPermission == false) {
      try {
        await overlayChannel.invokeMethod('requestOverlayPermission');
      } on PlatformException {}
    } else if (hasPermission == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          backgroundColor: kPrimaryPink,
          content: const Text(
            'Overlay (Üstte Gösterme) izni zaten verilmiş!',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          duration: Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      );
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "-";
    if (timestamp is Timestamp) {
      DateTime dt = timestamp.toDate();
      return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    if (timestamp is Map && timestamp.containsKey('_seconds')) {
      DateTime dt = DateTime.fromMillisecondsSinceEpoch(timestamp['_seconds'] * 1000);
      return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }
    if (timestamp is String && timestamp.contains('Timestamps(')) {
      final secMatch = RegExp(r'seconds=(\d+)').firstMatch(timestamp);
      if (secMatch != null) {
        int seconds = int.tryParse(secMatch.group(1) ?? "") ?? 0;
        DateTime dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        return "${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }
    }
    return timestamp.toString();
  }

  // Şifre Yenileme Popup ve İşlevleri (sadece yeni şifre)
    // Şifre Yenileme Popup ve İşlevleri (sadece yeni şifre)
  void _showPasswordResetPopup(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    String newPassword = '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Şifreyi Yenile"),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Yeni Şifre"),
                  validator: (val) => (val == null || val.length < 6)
                      ? "En az 6 karakter"
                      : null,
                  onChanged: (val) => newPassword = val,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text("İptal"),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text("Değiştir"),
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  Navigator.of(context).pop();
                  await Future.delayed(Duration(milliseconds: 100));
                  await _changePassword(newPassword);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Sadece Firebase ile şifreyi değiştirir (API kısmı kaldırıldı)
  Future<void> _changePassword(String newPassword) async {
    bool firebaseSuccess = false;
    String firebaseError = '';

    // 1. Firebase'de şifre değiştir
    try {
      final user = FirebaseAuth.instance.currentUser;
      debugPrint("DEBUG: user = $user");
      debugPrint("DEBUG: user?.uid = ${user?.uid}");
      debugPrint("DEBUG: user?.email = ${user?.email}");
      debugPrint("DEBUG: newPassword = $newPassword");

      if (user == null) throw Exception("Kullanıcı bulunamadı.");

      await user.updatePassword(newPassword);
      firebaseSuccess = true;
      debugPrint("DEBUG: updatePassword BAŞARILI");
    } on FirebaseAuthException catch (e) {
      firebaseError = e.message ?? e.code;
      debugPrint("DEBUG: updatePassword HATA: $e");
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text("Bu işlemi yapmak için tekrar giriş yapmanız gerekiyor! Lütfen çıkış yapıp tekrar giriş yapın.")),
        );
        return;
      }
    } catch (e) {
      firebaseError = e.toString();
      debugPrint("DEBUG: updatePassword BEKLENMEYEN HATA: $e");
    }

    // Sonuç bildirimi
    if (!mounted) return;
    if (firebaseSuccess) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text("Şifre başarıyla değiştirildi.")),
      );
    } else {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text("Şifre güncellenemedi.\nFirebase: $firebaseError")),
      );
    }
  }

 

  @override
  Widget build(BuildContext context) {
    pageContext = context;
    return Scaffold(
      backgroundColor: kProfileBg,
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: kPrimaryPurple,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle, size: 84, color: kPrimaryPurple),
              const SizedBox(height: 8),
              Text(
                'Profil Sayfası',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: kPrimaryPurple,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_accessibility, color: kPrimaryPurple),
                label: const Text("Erişilebilirlik Ayarlarını Aç", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryPink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: openAccessibilitySettings,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.privacy_tip, color: kPrimaryPurple),
                label: const Text(
                  "Kullanım Verisi İznini Aç",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryPink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: openUsageAccessSettings,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.layers, color: kPrimaryPurple),
                label: const Text("Overlay (Üstte Gösterme) İznini İste", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryPink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: checkAndRequestOverlayPermission,
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                icon: const Icon(Icons.lock_reset, color: kPrimaryPurple),
                label: const Text(
                  "Şifreyi Yenile",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryPink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  _showPasswordResetPopup(context);
                },
              ),
              const SizedBox(height: 32),
              if (_relatedUsers.isEmpty)
                Text("Kayıt bulunamadı.", style: TextStyle(color: kPrimaryPurple, fontSize: 15))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _relatedUsers.length,
                  itemBuilder: (context, idx) {
                    final data = _relatedUsers[idx];
                    final userDocId = data['id'];

                    if (userDocId.toString() == _userId.toString()) {
                      return const SizedBox.shrink();
                    }

                    final userType = data['user_type'] ?? '';
                    final userName = data['appcustomer_name'] ?? '';

                    final statusDoc = _internetStatusDocs[userDocId.toString()];
                    bool? internetConnected;
                    bool? appUninstalled;
                    bool? isOnline;

                    if (statusDoc != null) {
                      internetConnected = statusDoc['is_connected'] == true;
                      appUninstalled = statusDoc['app_uninstalled'] == true;
                      isOnline = statusDoc['online'] == true;
                    }

                    String internetText = "İnternet: Bilinmiyor";
                    Color internetColor = Colors.grey;
                    if (internetConnected == true) {
                      internetText = "İnternet: Var";
                      internetColor = Colors.green;
                    } else if (internetConnected == false) {
                      internetText = "İnternet: Yok";
                      internetColor = Colors.red;
                    }

                    String appUninstalledText = "Uygulama Yüklü";
                    Color appUninstalledColor = kPrimaryPurple;
                    if (appUninstalled == true) {
                      appUninstalledText = "Uygulama Kaldırılmış";
                      appUninstalledColor = kPrimaryPink;
                    }

                    String appStatusText = "Uygulama Durumu: Bilinmiyor";
                    Color appStatusColor = Colors.grey;
                    if (isOnline == true) {
                      appStatusText = "Uygulama Durumu: Açık";
                      appStatusColor = Colors.green;
                    } else if (isOnline == false) {
                      appStatusText = "Uygulama Durumu: Kapalı";
                      appStatusColor = Colors.red;
                    }

                    return Card(
                      color: kProfileBg,
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                      child: ListTile(
                        leading: Icon(Icons.person_pin_circle, color: kPrimaryPurple),
                        title: Text(
                          userName,
                          style: TextStyle(fontWeight: FontWeight.bold, color: kPrimaryPurple),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('User ID: $userDocId'),
                            Text('Rol: $userType'),
                            if (data.containsKey('last_active') && data['last_active'] != null)
                              Text('Son Güncel Tarih: ${_formatTimestamp(data['last_active'])}'),
                            Text(
                              internetText,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: internetColor,
                              ),
                            ),
                            Text(
                              appUninstalledText,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: appUninstalledColor,
                              ),
                            ),
                            Text(
                              appStatusText,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: appStatusColor,
                              ),
                            ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(
                            userType,
                            style: TextStyle(
                              color: kPrimaryPink,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: kPrimaryPink.withOpacity(0.12),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 32),
              Text(
                lastDetectedApp == null
                    ? "Hiç uygulama algılanmadı"
                    : "Algılanan uygulama: $lastDetectedApp",
                style: const TextStyle(fontSize: 16, color: kPrimaryPink, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
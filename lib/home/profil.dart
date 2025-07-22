import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

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

  late BuildContext pageContext;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeMessage);
    _loadUserInfo();
  }

  Future<void> _handleNativeMessage(MethodCall call) async {
    if (call.method == 'onAppDetected') {
      setState(() {
        lastDetectedApp = call.arguments?.toString();
      });
      debugPrint('Algılanan uygulama (native): ${call.arguments}');
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('user_id');
    _parentId = prefs.getInt('parent_id');
    _userType = prefs.getString('user_type');
    _userName = prefs.getString('appcustomer_name');
    setState(() {});
  }

  DateTime _getTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is Map && ts.containsKey('_seconds')) {
      return DateTime.fromMillisecondsSinceEpoch(ts['_seconds'] * 1000);
    }
    if (ts is DateTime) return ts;
    return DateTime.now();
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

  Future<void> _changePassword(String newPassword) async {
    bool firebaseSuccess = false;
    String firebaseError = '';

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Kullanıcı bulunamadı.");
      await user.updatePassword(newPassword);
      firebaseSuccess = true;
    } on FirebaseAuthException catch (e) {
      firebaseError = e.message ?? e.code;
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          const SnackBar(content: Text("Bu işlemi yapmak için tekrar giriş yapmanız gerekiyor! Lütfen çıkış yapıp tekrar giriş yapın.")),
        );
        return;
      }
    } catch (e) {
      firebaseError = e.toString();
    }

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
        backgroundColor: Colors.transparent,
        elevation: 2,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFBDA8AC),
                Color(0xFFF8F6F6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.black,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: kPrimaryPurple.withOpacity(0.13), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.settings_accessibility, color: Colors.brown),
                      label: const Text(
                        "Erişilebilirlik Ayarlarını Aç",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.brown,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.brown, width: 2),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: openAccessibilitySettings,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.privacy_tip, color: Colors.brown),
                      label: const Text(
                        "Kullanım Verisi İznini Aç",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.brown,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.brown, width: 2),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: openUsageAccessSettings,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.layers, color: Colors.brown),
                      label: const Text(
                        "Overlay (Üstte Gösterme) İznini İste",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.brown,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.brown, width: 2),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: checkAndRequestOverlayPermission,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.lock_reset, color: Colors.white),
                      label: const Text(
                        "Şifreyi Yenile",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.brown,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: Colors.brown, width: 2),
                        ),
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        _showPasswordResetPopup(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              StreamBuilder(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),
                builder: (context, AsyncSnapshot<QuerySnapshot> userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return CircularProgressIndicator();
                  }
                  final List<Map<String, dynamic>> relatedUsers = [];
                  for (var doc in userSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    if ((_userType == "Aile" && data['parent_id'] == _userId) ||
                        (_userType == "Cocuk" && (doc.id == _userId.toString() || doc.id == _parentId.toString()))) {
                      data['id'] = doc.id;
                      relatedUsers.add(data);
                    }
                  }
                  if (relatedUsers.isEmpty) {
                    return Text("Kayıt bulunamadı.", style: TextStyle(color: kPrimaryPurple, fontSize: 15));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: relatedUsers.length,
                    itemBuilder: (context, idx) {
                      final data = relatedUsers[idx];
                      final userDocId = data['id'];
                      if (userDocId.toString() == _userId.toString()) {
                        return const SizedBox.shrink();
                      }
                      final userType = data['user_type'] ?? '';
                      final userName = data['appcustomer_name'] ?? '';
                      DateTime? lastActive;
                      if (data.containsKey('last_active') && data['last_active'] != null) {
                        final ts = data['last_active'];
                        if (ts is Timestamp) {
                          lastActive = ts.toDate();
                        } else if (ts is Map && ts.containsKey('_seconds')) {
                          lastActive = DateTime.fromMillisecondsSinceEpoch(ts['_seconds'] * 1000);
                        } else if (ts is DateTime) {
                          lastActive = ts;
                        }
                      }
                      final now = DateTime.now();
                      bool isOnline = false;
                      if (lastActive != null) {
                        final diff = now.difference(lastActive);
                        isOnline = diff.inSeconds.abs() <= 10;
                      }
                      // Uygulama kaldırılmış mı kontrolü (SADECE USERS COLLECTION)
                      String appUninstalledText = "Uygulama Yüklü";
                      Color appUninstalledColor = Colors.black;
                      if (data.containsKey('app_uninstalled')) {
                        final appUninstalled = data['app_uninstalled'];
                        if (appUninstalled == true || appUninstalled == "true") {
                          appUninstalledText = "Uygulama Kaldırılmış";
                          appUninstalledColor = Colors.red;
                        }
                      }
                      String internetText = isOnline ? "İnternet: Var" : "İnternet: Yok";
                      Color internetColor = isOnline ? Colors.green : Colors.red;
                      String appStatusText = isOnline
                          ? "Uygulama Durumu: Açık"
                          : "Uygulama Durumu: Kapalı";
                      Color appStatusColor = isOnline ? Colors.black : Colors.red;
                      String lastActiveText = lastActive != null
                          ? _formatTimestamp(data['last_active'])
                          : "-";
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFBDA8AC),
                                Color(0xFFF8F6F6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(Icons.person_pin_circle, color: Colors.black),
                            title: Text(
                              userName,
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Rol: $userType',
                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,
                                    color: Colors.black,
                                  ),
                                ),
                                Text(
                                  'Son Güncel Tarih: $lastActiveText',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  internetText,
                                  style: TextStyle(
                                    fontWeight: FontWeight.normal,
                                    color: internetColor,
                                  ),
                                ),
                                Text(
                                  appUninstalledText,
                                  style: TextStyle(
                                    color: appUninstalledColor,
                                  ),
                                ),
                                Text(
                                  appStatusText,
                                  style: TextStyle(
                                    color: appStatusColor,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Color(0xFF8B5E3C),
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 27,
                                backgroundColor: Colors.white,
                                child: Text(
                                  '🧍',
                                  style: TextStyle(fontSize: 32),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
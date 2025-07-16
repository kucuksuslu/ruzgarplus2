import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'body.dart';
import 'searchbar.dart';
import 'not.dart';
import 'profil.dart';
import 'srocna.dart';
import 'chat_page.dart';
import '../deneme.sayfa.dart';
import '../background_service.dart';

// --- SABİT RENKLER ---
const Color accentPink = Color(0xFFFF1585);
const Color accentPurple = Color(0xFF5E17EB);
const Color lightPurple = Color(0xFFF6F2FB);

// --- Service setup and user functions ---
Future<void> startBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: true,
      autoStart: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: null,
    ),
  );
  await service.startService();
}

Future<void> updateLiveUserStatus({
  required int? currentUserId,
  required String? userType,
  required bool online,
  required String lastNotifiedAppStatus,
  required bool appExit,
  required FirebaseFirestore firestore,
}) async {
  if (currentUserId == null) return;
  final liveUsersDocRef = firestore.collection('live_users').doc(currentUserId.toString());
  final usersDocRef = firestore.collection('users').doc(currentUserId.toString());
  Map<String, dynamic> data = {
    'online': online,
    'last_notified_app_status': lastNotifiedAppStatus,
    'last_active': FieldValue.serverTimestamp(),
    'app_exit': appExit,
  };
  String? fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken != null) data['fcm_token'] = fcmToken;
  if (userType != null) data['filter'] = userType;
  data['user_id'] = currentUserId;
  await liveUsersDocRef.set(data, SetOptions(merge: true));
  await usersDocRef.set({
    'online': online,
    'last_active': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> logoutAll() async {
  try {
    await FirebaseAuth.instance.signOut();
  } catch (_) {}
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  } catch (_) {}
}

Future<Map<String, dynamic>> initializeUserAndLoadData(FirebaseFirestore firestore) async {
  final prefs = await SharedPreferences.getInstance();
  final int? userId = prefs.getInt('user_id');
  final String? userName = prefs.getString('appcustomer_name');
  final String? userType = prefs.getString('user_type');
  int? parentId = prefs.getInt('parent_id');
  if (parentId == null) {
    final Object? raw = prefs.get('parent_id');
    parentId = int.tryParse(raw?.toString() ?? '');
  }
  if (userId != null) {
    try {
      final userDocRef = firestore.collection('users').doc(userId.toString());
      await userDocRef.set({
        'user_id': userId,
        'appcustomer_name': userName ?? "",
        'user_type': userType ?? "",
        'parent_id': parentId,
        'created_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await firestore.collection('users').doc(userId.toString()).set({
          'fcm_token': fcmToken
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }
  return {
    'userId': userId,
    'userName': userName,
    'userType': userType,
    'parentId': parentId,
    'authToken': prefs.getString('auth_token'),
  };
}

Future<List<Map<String, dynamic>>> fetchChildrenFromFirebase(int currentUserId, FirebaseFirestore firestore) async {
  try {
    final snapshot = await firestore
        .collection('users')
        .where('parent_id', isEqualTo: currentUserId)
        .where('user_type', isEqualTo: 'Cocuk')
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>}).toList();
  } catch (_) {
    return [];
  }
}

Future<String?> addChild({
  required String childName,
  required String childEmail,
  required String childPassword,
  required String childTc,
  required String childPhone,
  required FirebaseFirestore firestore,
}) async {
  final prefs = await SharedPreferences.getInstance();
  int? parentUserId = prefs.getInt('user_id');
  if (parentUserId == null) return 'Parent user_id bulunamadı!';
  final childCountSnapshot = await firestore
      .collection('users')
      .where('parent_id', isEqualTo: parentUserId)
      .where('user_type', isEqualTo: 'Cocuk')
      .get();
  if (childCountSnapshot.docs.length >= 10) return 'En fazla 10 çocuk ekleyebilirsiniz!';
  if (childName.trim().isEmpty ||
      childEmail.trim().isEmpty ||
      childPassword.trim().isEmpty ||
      childTc.trim().isEmpty ||
      childPhone.trim().isEmpty) {
    return 'Tüm alanları doldurun.';
  }
  try {
    final snapshot = await firestore
        .collection('users')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get();
    int lastUserId = 0;
    if (snapshot.docs.isNotEmpty) {
      lastUserId = int.tryParse(snapshot.docs.first.id) ?? 0;
    }
    int newUserId = lastUserId + 1;
    UserCredential childCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: childEmail,
      password: childPassword,
    );
    final childUser = childCredential.user;
    if (childUser == null) throw Exception("Çocuk kullanıcısı oluşturulamadı!");
    await firestore.collection('users').doc(newUserId.toString()).set({
      'user_id': newUserId,
      'appcustomer_name': childName,
      'appcustomer_email': childEmail,
      'appcustomer_tc': childTc,
      'app_phone': childPhone,
      'user_type': 'Cocuk',
      'parent_id': parentUserId,
      'created_at': FieldValue.serverTimestamp(),
      'firebase_uid': childUser.uid,
    });
    String? parentEmail = prefs.getString('user_email');
    String? parentPassword = prefs.getString('user_password');
    if (parentEmail != null && parentPassword != null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: parentEmail,
        password: parentPassword,
      );
    }
    return null;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') return 'Bu e-posta ile zaten bir çocuk hesabı var!';
    if (e.code == 'weak-password') return 'Şifre en az 6 karakter olmalı!';
    if (e.code == 'invalid-email') return 'Geçersiz e-posta adresi!';
    return 'Kayıt başarısız: ${e.message}';
  } catch (e) {
    return 'Bir hata oluştu: $e';
  }
}

Future<String?> deleteChild(String childDocId, FirebaseFirestore firestore) async {
  try {
    final childDoc = await firestore.collection('users').doc(childDocId).get();
    String? childEmail = childDoc.data()?['appcustomer_email'];
    String? childPassword = null;
    await firestore.collection('users').doc(childDocId).delete();
    if (childEmail != null && childPassword != null) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: childEmail,
          password: childPassword,
        );
        await FirebaseAuth.instance.currentUser?.delete();
        final prefs = await SharedPreferences.getInstance();
        String? parentEmail = prefs.getString('user_email');
        String? parentPassword = prefs.getString('user_password');
        if (parentEmail != null && parentPassword != null) {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: parentEmail,
            password: parentPassword,
          );
        }
      } catch (_) {}
    }
    return null;
  } catch (e) {
    return 'Bir hata oluştu: $e';
  }
}

Future<void> addOrUpdateChildProfileImage(String childDocId, FirebaseFirestore firestore) async {
  final picker = ImagePicker();
  final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
  if (pickedFile == null) return;
  final File imageFile = File(pickedFile.path);
  final imgurUrl = await uploadImageToImgur(imageFile);
  if (imgurUrl != null) {
    try {
      await firestore.collection('users').doc(childDocId).update({'profile_image_url': imgurUrl});
      await firestore.collection('user_locations').doc(childDocId).set({'profile_image_url': imgurUrl}, SetOptions(merge: true));
    } catch (_) {}
  }
}

Future<String?> uploadImageToImgur(File imageFile) async {
  final bytes = await imageFile.readAsBytes();
  final base64Image = base64Encode(bytes);
  final response = await http.post(
    Uri.parse('https://api.imgur.com/3/image'),
    headers: {'Authorization': 'Client-ID 44695e9d165faae'},
    body: {
      'image': base64Image,
      'type': 'base64',
    },
  );
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['data']['link'];
  } else {
    return null;
  }
}

void setupFCMListeners() async {
  await FirebaseMessaging.instance.requestPermission();
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {});
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {});
}

// --- BookPageView (content card) UZUN, BOŞLUKSUZ, RESİM KÜÇÜK VE ORTADA --- //
class BookPageView extends StatefulWidget {
  final List<DocumentSnapshot> docs;
  const BookPageView({super.key, required this.docs});

  @override
  State<BookPageView> createState() => _BookPageViewState();
}

class _BookPageViewState extends State<BookPageView> {
  PageController _controller = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final total = widget.docs.length;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: total,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemBuilder: (context, index) {
              final data = widget.docs[index].data() as Map<String, dynamic>;
              return Container(
                width: screenWidth,
                // En uzun scrollable içerik için
                constraints: BoxConstraints(
                  minWidth: screenWidth,
                  minHeight: screenHeight,
                  maxWidth: screenWidth,
                  maxHeight: screenHeight,
                ),
                child: Card(
                  elevation: 20,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(40),
                  ),
                  color: Colors.white,
                  margin: EdgeInsets.zero,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          data['title'] ?? "Başlıksız",
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: accentPurple,
                            letterSpacing: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        if (data['image_url'] != null &&
                            data['image_url'].toString().isNotEmpty)
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.network(
                                data['image_url'],
                                width: screenWidth * 0.35,
                                height: screenHeight * 0.16,
                                fit: BoxFit.contain,
                                errorBuilder: (c, e, s) => Icon(Icons.broken_image, size: 50, color: accentPink),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          (data['content'] ?? data['description'] ?? ""),
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.justify,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: _currentPage > 0
                    ? () => _controller.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut)
                    : null,
              ),
              Text(
                "Sayfa ${_currentPage + 1} / $total",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: accentPurple),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: _currentPage < total - 1
                    ? () => _controller.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<List<DocumentSnapshot>> _fetchAllContent(
    String category, String? userType, FirebaseFirestore firestore) async {
  final creatorsSnap = await firestore
      .collection('content_creators')
      .where('category', isEqualTo: userType)
      .get();
  final contentSnap = await firestore
      .collection('content')
      .where('category', isEqualTo: userType)
      .get();
  return [...creatorsSnap.docs, ...contentSnap.docs];
}

Widget buildContentBookForCategory(
    String category, String? userType, FirebaseFirestore firestore) {
  return FutureBuilder<List<DocumentSnapshot>>(
    future: _fetchAllContent(category, userType, firestore),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final docs = snapshot.data ?? [];
      if (docs.isEmpty) {
        return const Center(child: Text("İçerik bulunamadı."));
      }
      return BookPageView(docs: docs); // Padding yok, tam ekran!
    },
  );
}

class PaginatedChildrenList extends StatefulWidget {
  final List<Map<String, dynamic>> children;
  final void Function() refresh;
  final Future<void> Function(String childDocId) onDelete;
  final Future<void> Function(String childDocId) onProfileImageUpdate;
  const PaginatedChildrenList({
    super.key,
    required this.children,
    required this.refresh,
    required this.onDelete,
    required this.onProfileImageUpdate,
  });

  @override
  State<PaginatedChildrenList> createState() => _PaginatedChildrenListState();
}

class _PaginatedChildrenListState extends State<PaginatedChildrenList> {
  int pageIndex = 0;
  static const int childrenPerPage = 2;

  @override
  Widget build(BuildContext context) {
    final totalPages =
        (widget.children.length / childrenPerPage).ceil().clamp(1, 999);
    final start = pageIndex * childrenPerPage;
    final end = (start + childrenPerPage).clamp(0, widget.children.length);
    final childrenOnPage = widget.children.sublist(start, end);

    return Column(
      children: [
        ...childrenOnPage.map((child) {
          final childDocId = child['id'] as String;
          final profileImageUrl = child['profile_image_url'] as String?;
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            color: lightPurple,
            child: ListTile(
              leading: GestureDetector(
                onTap: () async {
                  await widget.onProfileImageUpdate(childDocId);
                  widget.refresh();
                },
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: accentPink.withOpacity(0.16),
                  backgroundImage: (profileImageUrl != null &&
                          profileImageUrl.startsWith('http'))
                      ? NetworkImage(profileImageUrl)
                      : null,
                  child: (profileImageUrl == null)
                      ? const Icon(Icons.add_a_photo,
                          color: accentPurple, size: 28)
                      : null,
                ),
              ),
              title: Text(
                child['appcustomer_name'] ?? "",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: accentPurple,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: accentPink, size: 28),
                onPressed: () async {
                  await widget.onDelete(childDocId);
                  widget.refresh();
                },
              ),
            ),
          );
        }).toList(),
        if (widget.children.length > childrenPerPage)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: pageIndex > 0
                      ? () => setState(() => pageIndex--)
                      : null,
                ),
                Text(
                  "Sayfa ${pageIndex + 1} / $totalPages",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: pageIndex < totalPages - 1
                      ? () => setState(() => pageIndex++)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Panel functions ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int? _currentUserId;
  String? _currentUserName;
  String? _currentUserToken;
  String? _userType;
  int? _parentId;
  List<Map<String, dynamic>> _children = [];
  Timer? _heartbeatTimer;

  static const Color accentPink = Color(0xFFFF1585);
  static const Color accentPurple = Color(0xFF5E17EB);
  static const Color lightPurple = Color(0xFFF6F2FB);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    startBackgroundService();
    setupFCMListeners();
    initializeUserAndLoadData(_firestore).then((userData) async {
      setState(() {
        _currentUserId = userData['userId'];
        _currentUserName = userData['userName'];
        _currentUserToken = userData['authToken'];
        _userType = userData['userType'];
        _parentId = userData['parentId'];
      });
      if (_userType == 'Aile' && _currentUserId != null) {
        List<Map<String, dynamic>> children = await fetchChildrenFromFirebase(_currentUserId!, _firestore);
        setState(() => _children = children);
      }
      if (_currentUserId != null) {
        updateLiveUserStatus(
          currentUserId: _currentUserId,
          userType: _userType,
          online: true,
          lastNotifiedAppStatus: "Uygulama açık",
          appExit: false,
          firestore: _firestore,
        );
      }
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    if (_currentUserId != null) {
      updateLiveUserStatus(
        currentUserId: _currentUserId,
        userType: _userType,
        online: false,
        lastNotifiedAppStatus: "Uygulama kapalı",
        appExit: true,
        firestore: _firestore,
      );
    }
    logoutAll();
    super.dispose();
  }

  Widget buildAilePanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(3.0),
          child: ElevatedButton.icon(
            onPressed: () {
              String childName = '';
              String childEmail = '';
              String childPassword = '';
              String childTc = '';
              String childPhone = '';
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    backgroundColor: lightPurple,
                    title: const Text('Yeni Çocuk Ekle',
                        style: TextStyle(color: accentPurple)),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            onChanged: (val) => childName = val,
                            decoration: const InputDecoration(
                              hintText: 'Çocuğun Adı',
                            ),
                          ),
                          TextField(
                            onChanged: (val) => childEmail = val,
                            decoration: const InputDecoration(
                              hintText: 'Çocuğun E-posta',
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          TextField(
                            obscureText: true,
                            onChanged: (val) => childPassword = val,
                            decoration: const InputDecoration(
                              hintText: 'Çocuğun Şifresi',
                            ),
                          ),
                          TextField(
                            onChanged: (val) => childTc = val,
                            decoration: const InputDecoration(
                              hintText: 'Çocuğun TC Kimlik No',
                            ),
                            keyboardType: TextInputType.number,
                            maxLength: 11,
                          ),
                          TextField(
                            onChanged: (val) => childPhone = val,
                            decoration: const InputDecoration(
                              hintText: 'Çocuğun Telefon Numarası',
                            ),
                            keyboardType: TextInputType.phone,
                            maxLength: 11,
                          ),
                        ],
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('İptal', style: TextStyle(color: accentPurple)),
                        onPressed: () { Navigator.of(context).pop(); },
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentPink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('Ekle'),
                        onPressed: () async {
                          String? errMsg = await addChild(
                            childName: childName,
                            childEmail: childEmail,
                            childPassword: childPassword,
                            childTc: childTc,
                            childPhone: childPhone,
                            firestore: _firestore,
                          );
                          if (errMsg == null) {
                            List<Map<String, dynamic>> children = await fetchChildrenFromFirebase(_currentUserId!, _firestore);
                            setState(() => _children = children);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Çocuk başarıyla eklendi!')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(errMsg)),
                            );
                          }
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            },
            icon: const Icon(Icons.person_add, color: accentPink),
            label: const Text('Yeni Çocuk Ekle'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
              backgroundColor: accentPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 1,
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              if (_children.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(1.0),
                  child: Center(
                    child: Text(
                      'Henüz eklenmiş bir çocuk yok.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
  child: PaginatedChildrenList(
    children: _children,
    refresh: () async {
      List<Map<String, dynamic>> children = await fetchChildrenFromFirebase(_currentUserId!, _firestore);
      setState(() => _children = children);
    },
    onDelete: (childDocId) => deleteChild(childDocId, _firestore),
    onProfileImageUpdate: (childDocId) => addOrUpdateChildProfileImage(childDocId, _firestore),
  ),
),
// Hiç padding veya SizedBox koyma!
Text(
  "Aile Kategorisi İçerikleri",
  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
),
Expanded(child: buildContentBookForCategory("Aile", _userType, _firestore)),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildCocukPanel() {
    return Column(
      children: [
        Text('Hoşgeldin Çocuk! (Kullanıcı ID: $_currentUserId)'),
        if (_parentId != null)
          FutureBuilder<DocumentSnapshot>(
            future: _firestore.collection('users').doc(_parentId.toString()).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const CircularProgressIndicator();
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              return Text(
                  'Bağlı Olduğun Aile: ${data?['appcustomer_name'] ?? "Bilinmiyor"}');
            },
          ),
        const SizedBox(height: 10),
        const Text(
          "Çocuk Kategorisi İçerikleri",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Expanded(child: buildContentBookForCategory("Çocuk", _userType, _firestore)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildAilePanel(),
      SearchPage(),
      NotificationsPage(),
      ProfilePage(),
      const SrocniyPage(),
      ChatPage(),
      DenemeSayfa(),
    ];
    return Scaffold(
      backgroundColor: lightPurple,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/ruzgarplus.png', height: 50),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentPink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        elevation: 2,
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      onPressed: () {
                        setState(() { _currentIndex = 5; });
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mesajlaşma'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: pages[_currentIndex]),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 30),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            selectedItemColor: accentPink,
            unselectedItemColor: accentPurple.withOpacity(0.5),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
            onTap: (index) {
              setState(() {
                _currentIndex = index;
                if (_currentIndex == 0 && _userType == 'Aile' && _currentUserId != null) {
                  fetchChildrenFromFirebase(_currentUserId!, _firestore).then((children) {
                    setState(() => _children = children);
                  });
                }
              });
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Ana Sayfa'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Konum Bul'),
              BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Uygulama Denetimi'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
              BottomNavigationBarItem(icon: Icon(Icons.warning_amber_rounded, color: accentPink), label: 'Acil Çağrı'),
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Mesajlaşma'),
              BottomNavigationBarItem(icon: Icon(Icons.hearing), label: 'Dinleme'),
            ],
          ),
        ),
      ),
    );
  }
}
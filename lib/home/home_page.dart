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
import 'dart:math';
import 'body.dart';
import 'searchbar.dart';
import 'not.dart';
import 'profil.dart';
import 'srocna.dart';
import 'chat_page.dart';
import '../deneme.sayfa.dart';
import '../background_service.dart';
import 'package:url_launcher/url_launcher.dart';
// --- SABİT RENKLER ---
const Color accentPink = Color(0xFFFF1585);
const Color accentPurple = Color(0xFF5E17EB);
const Color lightPurple = Color(0xFFF6F2FB);

// --- TÜM FONKSİYONLAR ---
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
Future<String?> updateAndSaveFCMToken(FirebaseFirestore firestore, int userId) async {
  String? fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken != null && fcmToken.isNotEmpty) {
    await firestore.collection('users').doc(userId.toString()).set({
      'fcm_token': fcmToken
    }, SetOptions(merge: true));
  }
  return fcmToken;
}
Future<void> handleFCMErrorIfNeeded(
    FirebaseFirestore firestore, int userId, http.Response response) async {
  if (response.statusCode == 400 && response.body.contains("not a valid FCM registration token")) {
    // Tokenı sil ve yenile
    await FirebaseMessaging.instance.deleteToken();
    await updateAndSaveFCMToken(firestore, userId);
  }
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
  String? fcmToken = await updateAndSaveFCMToken(firestore, currentUserId);
  if (fcmToken != null) data['fcm_token'] = fcmToken;
  if (userType != null) data['userType'] = userType;
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

// --- AnimatedDownArrow: İçeriklerin sağ alt köşesinde, overflow güvenli. ---
class AnimatedDownArrow extends StatefulWidget {
  final EdgeInsetsGeometry? padding;
  const AnimatedDownArrow({Key? key, this.padding}) : super(key: key);

  @override
  State<AnimatedDownArrow> createState() => _AnimatedDownArrowState();
}
class _AnimatedDownArrowState extends State<AnimatedDownArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: 24).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding ?? const EdgeInsets.only(top: 6, bottom: 2, right: 10),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 42,
          color: accentPurple.withOpacity(0.8),
        ),
      ),
    );
  }
}

// --- Yatay çocuk listesi: Overflow güvenli, min boyutlar! ---
class HorizontalChildrenList extends StatelessWidget {
  final List<Map<String, dynamic>> children;
  final void Function() refresh;
  final Future<void> Function(String childDocId) onDelete;
  final Future<void> Function(String childDocId) onProfileImageUpdate;

  const HorizontalChildrenList({
    super.key,
    required this.children,
    required this.refresh,
    required this.onDelete,
    required this.onProfileImageUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const Center(
        child: Text(
          'Henüz eklenmiş bir çocuk yok.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SizedBox(
      height: 120, // Burayı artır! (140, 150, 160 deneyebilirsin)
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final child = children[index];
          final childDocId = child['id'] as String;
          final profileImageUrl = child['profile_image_url'] as String?;
return Container(
  width: 200,
  height: 150,
  child: Card(
    elevation: 4, // daha belirgin gölge
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: Color(0xFF8D6E63), // kahverengi kenar
        width: 2,
      ),
    ),
    color: Color(0xFFFFF8E1), // krem arkaplan
    shadowColor: Color(0xFF8D6E63).withOpacity(0.15), // kahverengi gölge
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
 colors: [
    Color(0xFFBDA8AC), // kenar rengi (bda8ac)
    Color(0xFFF8F6F6), // iç arkaplan (5c4448)
  ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () async {
                await onProfileImageUpdate(childDocId);
                refresh();
              },
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.black,
                backgroundImage: (profileImageUrl != null && profileImageUrl.startsWith('http'))
                    ? NetworkImage(profileImageUrl)
                    : null,
                child: (profileImageUrl == null)
                    ? Icon(Icons.add_a_photo, color: Colors.white, size: 19)
                    : null,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                child['appcustomer_name'] ?? "",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black,
                  letterSpacing: 0.18,
                  shadows: [
                    Shadow(
                      color: accentPurple.withOpacity(0.09),
                      offset: Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            Container(
              width: 2.5,
              height: 46,
              margin: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: accentPurple.withOpacity(0.25),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
   Container(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(9),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        "Sil",
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      GestureDetector(
        onTap: () async {
          await onDelete(childDocId);
          refresh();
        },
        child: Icon(
          Icons.delete,
          color: Colors.black,
          size: 22,
        ),
      ),
    ],
  ),
)
          ],
        ),
      ),
    ),
  ),
);
        },
      ),
    );
  }
}

// --- BookPageView: İçerik ve sağ altta ok animasyonu ---
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

    // Kart genişliğini azaltmak için maxWidth'i belirliyoruz (ör: ekranın %80'i)
    final double cardWidth = min(screenWidth * 0.8, 310);

    return Stack(
      children: [
        Column(
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
                  return Center(
                    child: Container(
                      width: cardWidth,
                      constraints: BoxConstraints(
                        minWidth: 180,
                        maxWidth: cardWidth,
                        minHeight: screenHeight * 0.5,
                        maxHeight: screenHeight,
                      ),
                      child: Card(
                        elevation: 15,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                        color: Colors.white,
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                data['title'] ?? "Başlıksız",
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  letterSpacing: 1.1,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10), // Başlık ile resim arası boşluk
                              if (data['image_url'] != null && data['image_url'].toString().isNotEmpty)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 7.0), // Resmin üst-altına boşluk!
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(28),
                                      child: Image.network(
                                        data['image_url'],
                                        width: cardWidth * 0.34, // Genişlik azaltıldı!
                                        height: screenHeight * 0.20,
                                        fit: BoxFit.contain,
                                        errorBuilder: (c, e, s) => Icon(Icons.broken_image, size: 56, color: accentPink),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8), // Resim ile içerik arası boşluk
                              Text(
                                (data['content'] ?? data['description'] ?? ""),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black87,
                                  height: 1.38,
                                ),
                                textAlign: TextAlign.justify,
                              ),
                            ],
                          ),
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
        ),
        // AnimatedDownArrow widget'ın örneğini eklemelisin veya comment-out yapabilirsin
        // Positioned(
        //   right: 8,
        //   bottom: 18,
        //   child: AnimatedDownArrow(),
        // ),
      ],
    );
  }
}

Future<List<DocumentSnapshot>> _fetchAllContent(
    String category, String? userType, FirebaseFirestore firestore) async {
  final creatorsSnap = await firestore
      .collection('content_creators')
      .where('category', isEqualTo: category)
      .get();
  return [...creatorsSnap.docs];
}
Widget _contentCard(BuildContext context, DocumentSnapshot doc, String titleLabel) {
  final data = doc.data() as Map<String, dynamic>;
  final double cardWidth = min(MediaQuery.of(context).size.width * 0.32, 350);
  final double screenHeight = MediaQuery.of(context).size.height;

  return Card(
    elevation: 10,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    color: Colors.white,
    child: Container(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titleLabel,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data['title'] ?? "Başlıksız",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (data['image_url'] != null && data['image_url'].toString().isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                data['image_url'],
                width: cardWidth * 0.90,
                height: min(120, screenHeight * 0.16),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 36, color: accentPink),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            (data['content'] ?? data['description'] ?? ""),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.32,
            ),
            textAlign: TextAlign.justify,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
Widget _splitCardSection(
    BuildContext context, DocumentSnapshot doc, String label, bool left) {
  final data = doc.data() as Map<String, dynamic>;
  final double cardWidth = min(MediaQuery.of(context).size.width * 0.42, 400);
  final double screenHeight = MediaQuery.of(context).size.height;

  return Padding(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Column(
      crossAxisAlignment:
          left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: accentPurple,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          data['title'] ?? "Başlıksız",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          textAlign: left ? TextAlign.left : TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        if (data['image_url'] != null && data['image_url'].toString().isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              data['image_url'],
              width: cardWidth * 0.70,
              height: min(80, screenHeight * 0.54),
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) =>
                  Icon(Icons.broken_image, size: 30, color: accentPink),
            ),
          ),
    
       
      ],
    ),
  );
}
Widget _onlyImageLinkSection(BuildContext context, DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final double cardWidth = min(MediaQuery.of(context).size.width * 0.42, 400);
  final double screenHeight = MediaQuery.of(context).size.height;

  // Uzun link için veri: image_url (resim), link_url (link)
  final String? imageUrl = data['image_url'] as String?;
  final String? linkUrl = data['link_url'] as String?;

  return Padding(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (imageUrl != null && imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              imageUrl,
              width: cardWidth * 0.90,
              height: min(120, screenHeight * 0.17),
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) =>
                  Icon(Icons.broken_image, size: 36, color: accentPink),
            ),
          ),
        const SizedBox(height: 14),
        if (linkUrl != null && linkUrl.isNotEmpty)
          InkWell(
            onTap: () async {
              if (await canLaunchUrl(Uri.parse(linkUrl))) {
                await launchUrl(Uri.parse(linkUrl), mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                linkUrl,
                style: TextStyle(
                  color: accentPurple,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  decoration: TextDecoration.underline,
                ),
                textAlign: TextAlign.center,
                maxLines: 5, // Linki tam uzun gösterir, ekrana taşarsa kaydırır
                overflow: TextOverflow.visible, // Tüm linki göster
              ),
            ),
          ),
      ],
    ),
  );
}
Widget _fullImageTitleLinkSection(BuildContext context, DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final String? imageUrl = data['image_url'] as String?;
  final String? linkUrl = data['content'] as String?;
  final String? title = data['title'] as String?;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      if (title != null && title.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      Expanded(
        child: imageUrl != null && imageUrl.isNotEmpty && linkUrl != null && linkUrl.isNotEmpty
            ? InkWell(
               onTap: () async {
  final uri = Uri.parse(linkUrl!);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Link açılamıyor: $linkUrl'))
    );
  }
},
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    imageUrl,
                      width: 150,  
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        Icon(Icons.broken_image, size: 40, color: accentPink),
                  ),
                ),
              )
            : Container(
                color: Colors.grey[200],
                child: Icon(Icons.image, size: 40, color: Colors.grey),
                width: double.infinity,
                height: double.infinity,
              ),
      ),
    ],
  );
}
Widget buildContentSplitForCategory(
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
      // İlk iki içerik
      final first = docs.isNotEmpty ? docs[0] : null;
      final second = docs.length > 1 ? docs[1] : null;

      final double cardWidth = MediaQuery.of(context).size.width * 0.96;
      final double cardHeight = min(MediaQuery.of(context).size.height * 0.47, 350);

      return Center(
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          color: Colors.white,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Sol bölüm: İlk içerik
                Expanded(
                  child: first == null
                      ? Center(child: Text("İlk içerik yok"))
                      : _fullImageTitleLinkSection(context, first),
                ),
                // Dikey ayraç
                Container(
                  width: 2.5,
                  height: double.infinity,
                  color: accentPurple.withOpacity(0.15),
                ),
                // Sağ bölüm: İkinci içerik
                Expanded(
                  child: second == null
                      ? Center(child: Text("İkinci içerik yok"))
                      : _fullImageTitleLinkSection(context, second),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}


// --- HomePage ve panel kodu ---
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
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (_currentUserId == null) return;
  if (state == AppLifecycleState.detached) {
    // Uygulama tamamen kapandı
    updateLiveUserStatus(
      currentUserId: _currentUserId,
      userType: _userType,
      online: false,
      lastNotifiedAppStatus: "Uygulama kapalı",
      appExit: true,
      firestore: _firestore,
    );
  } else if (state == AppLifecycleState.resumed) {
    // Uygulama tekrar öne geldi, online yap
    updateLiveUserStatus(
      currentUserId: _currentUserId,
      userType: _userType,
      online: true,
      lastNotifiedAppStatus: "Uygulama açık",
      appExit: false,
      firestore: _firestore,
    );
  }
  // paused ve inactive için hiçbir şey yapma!
}
  @override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  _heartbeatTimer?.cancel();
  if (_currentUserId != null) {
    // Uygulama tamamen kapanınca offline yap
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
                  return Dialog(
                    backgroundColor: lightPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
       child: SingleChildScrollView(
  child: Center(
    child: Container(
      width: 280, // Genişlik ayarı
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Color(0xFF6B5048),
              child: const Icon(Icons.person_add, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              'Yeni Çocuk Ekle',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 14),
          SizedBox(
  height: 48,
  child: TextField(
    decoration: InputDecoration(
  hintText: 'Çocuğun Adı',
  prefixIcon: Padding(
    padding: EdgeInsets.only(left: 8), // Solda 8px boşluk
    child: Icon(Icons.person, size: 16, color: Colors.black),
  ),
  prefixIconConstraints: BoxConstraints(minHeight: 32, minWidth: 32), // minWidth'i biraz artırabilirsin!
  filled: true,
  fillColor: Color(0xFF8D6E63).withOpacity(0.15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.black, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white, width: 2),
  ),
  contentPadding: EdgeInsets.zero,
  isDense: true,
),
    style: TextStyle(fontSize: 13),
  ),
),
            
          const SizedBox(height: 8),
SizedBox(
  height: 48,
  child: TextField(
    onChanged: (val) => childEmail = val,
   decoration: InputDecoration(
  hintText: 'Çocuğun E-posta',
  prefixIcon: Padding(
    padding: EdgeInsets.only(left: 8), // Solda 8px boşluk
    child: Icon(Icons.email, size: 16, color: Colors.black),
  ),
  prefixIconConstraints: BoxConstraints(minHeight: 32, minWidth: 32), // minWidth'i biraz artırdık
  filled: true,
  fillColor: Color(0xFF8D6E63).withOpacity(0.15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.black, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white, width: 2),
  ),
  contentPadding: EdgeInsets.zero,
  isDense: true,
),
    keyboardType: TextInputType.emailAddress,
    style: TextStyle(fontSize: 13),
  ),
),
const SizedBox(height: 8),
SizedBox(
  height: 48,
  child: TextField(
    obscureText: true,
    onChanged: (val) => childPassword = val,
  decoration: InputDecoration(
  hintText: 'Çocuğun Şifresi',
  prefixIcon: Padding(
    padding: EdgeInsets.only(left: 8), // Solda 8px boşluk
    child: Icon(Icons.lock, size: 16, color: Colors.black),
  ),
  prefixIconConstraints: BoxConstraints(minHeight: 32, minWidth: 32), // minWidth biraz artırıldı
  filled: true,
  fillColor: Color(0xFF8D6E63).withOpacity(0.15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.black, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white, width: 2),
  ),
  contentPadding: EdgeInsets.zero,
  isDense: true,
),
    style: TextStyle(fontSize: 13),
  ),
),
const SizedBox(height: 8),
SizedBox(
  height: 48,
  child: TextField(
    onChanged: (val) => childTc = val,
 decoration: InputDecoration(
  hintText: 'Çocuğun TC Kimlik No',
  prefixIcon: Padding(
    padding: EdgeInsets.only(left: 8), // Solda 8px boşluk
    child: Icon(Icons.credit_card, size: 16, color: Colors.black),
  ),
  prefixIconConstraints: BoxConstraints(minHeight: 32, minWidth: 32), // minWidth artırıldı
  filled: true,
  fillColor: Color(0xFF8D6E63).withOpacity(0.15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.black, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white, width: 2),
  ),
  contentPadding: EdgeInsets.zero,
  isDense: true,
  counterText: '',
),
    keyboardType: TextInputType.number,
    maxLength: 11,
    style: TextStyle(fontSize: 13),
  ),
),
const SizedBox(height: 8),
SizedBox(
  height: 48,
  child: TextField(
    onChanged: (val) => childPhone = val,
   decoration: InputDecoration(
  hintText: 'Çocuğun Telefon Numarası',
  prefixIcon: Padding(
    padding: EdgeInsets.only(left: 8), // Solda 8px boşluk
    child: Icon(Icons.phone, size: 16, color: Colors.black),
  ),
  prefixIconConstraints: BoxConstraints(minHeight: 32, minWidth: 32), // minWidth artırıldı
  filled: true,
  fillColor: Color(0xFF8D6E63).withOpacity(0.15),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.black, width: 1.5),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: Colors.white, width: 2),
  ),
  contentPadding: EdgeInsets.zero,
  isDense: true,
  counterText: '',
),
    keyboardType: TextInputType.phone,
    maxLength: 11,
    style: TextStyle(fontSize: 13),
  ),
),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text(
                    'İptal',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Color(0xFF6B5048),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add, color: Colors.white),
                  label: const Text('Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF6B5048),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
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
                        SnackBar(
                          content: const Text('Çocuk başarıyla eklendi!'),
                          backgroundColor: accentPurple,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errMsg),
                          backgroundColor: accentPink,
                        ),
                      );
                    }
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
)
                  );
                },
              );
            },
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text('Yeni Çocuk Ekle'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 1,
            ),
          ),
        ),
        HorizontalChildrenList(
          children: _children,
          refresh: () async {
            List<Map<String, dynamic>> children = await fetchChildrenFromFirebase(_currentUserId!, _firestore);
            setState(() => _children = children);
          },
          onDelete: (childDocId) => deleteChild(childDocId, _firestore),
          onProfileImageUpdate: (childDocId) => addOrUpdateChildProfileImage(childDocId, _firestore),
        ),
        Text(
          "Aile Kategorisi İçerikleri",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Expanded(child: buildContentSplitForCategory("Aile", _userType, _firestore)),
      ],
    );
  }
Widget buildCocukSplitContentCard(
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
      // İlk iki içerik
      final first = docs.isNotEmpty ? docs[0] : null;
      final second = docs.length > 1 ? docs[1] : null;

      final double cardWidth = MediaQuery.of(context).size.width * 0.96;
      final double cardHeight = min(MediaQuery.of(context).size.height * 0.52, 400);

      return Center(
        child: Card(
          elevation: 14,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          color: Colors.white,
          child: Container(
            width: cardWidth,
            height: cardHeight,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Sol bölüm: İlk içerik
                Expanded(
                  child: first == null
                      ? Center(child: Text("İlk içerik yok"))
                      : Padding(
                          padding: const EdgeInsets.only(right: 8), // Sağda daha az boşluk
                          child: _fullImageTitleLinkSection(context, first),
                        ),
                ),
                // İnce ayraç
                Container(
                  width: 1,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: accentPurple.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Sağ bölüm: İkinci içerik
                Expanded(
                  child: second == null
                      ? Center(child: Text("İkinci içerik yok"))
                      : Padding(
                          padding: const EdgeInsets.only(left: 8), // Solda daha az boşluk
                          child: _fullImageTitleLinkSection(context, second),
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget buildCocukPanel() {
  return Column(
    children: [
      
      if (_parentId != null)
        
      const Padding(
        padding: EdgeInsets.only(top: 8.0, bottom: 8.0),
        child: Text(
          "Sosyal İçerikler",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: buildCocukSplitContentCard("çocuk", _userType, _firestore),
        ),
      ),
    ],
  );
}
  @override
Widget build(BuildContext context) {
  final List<Widget> pages = _userType == 'Cocuk'
      ? [
          buildCocukPanel(),
          SearchPage(),
          NotificationsPage(),
          ProfilePage(),
          const SrocniyPage(),
          DenemeSayfa(),
         
        ]
      : [
          buildAilePanel(),
          SearchPage(),
          NotificationsPage(),
          ProfilePage(),
          const SrocniyPage(),
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
                Image.asset('assets/ruzgarplus5.png', height: 60),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      elevation: 2,
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  onPressed: () {
  Navigator.push(context, MaterialPageRoute(builder: (context) => ChatPage()));
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
    bottomNavigationBar: Container(
      width: MediaQuery.of(context).size.width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: accentPink,
        unselectedItemColor: accentPurple.withOpacity(0.5),
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
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
        items: [
          BottomNavigationBarItem(
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),

                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.home, color: Colors.black),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Container(
           width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),

                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/ruzgarplusicon.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
              ),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Container(
                width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),

                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.notifications, color: Colors.black),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Container(
             width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),

                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.person, color: Colors.black),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),

                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.warning_amber_rounded, color: Colors.black),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Container(
                width: 48,
              height: 48,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.brown, width: 2),
                color: Color(0xFF8D6E63).withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.hearing, color: Colors.black),
            ),
            label: '',
          ),
        ],
      ),
    ),
  );
}
}
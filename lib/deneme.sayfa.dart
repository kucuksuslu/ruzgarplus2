import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:google_fonts/google_fonts.dart';

const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);
const Color kWaveBlue = Color(0xFF248AFF);

class DenemeSayfa extends StatefulWidget {
  const DenemeSayfa({super.key});

  @override
  State<DenemeSayfa> createState() => _DenemeSayfaState();
}

class _DenemeSayfaState extends State<DenemeSayfa> with SingleTickerProviderStateMixin {
  String _debugText = "Hazır";
  int? _currentUserId;
  int? _parentId;
  String? _userType;
  String? _selectedUserId; // çocuk veya aile user_id'si
  List<Map<String, dynamic>> _chatUsers = [];
  double _userMoney = 0;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _freqRoomSubscription;
  String? _lastRoomStatus;

  bool isListening = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfoAndChatUsers();
  }

  Future<void> _loadUserInfoAndChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final parentId = prefs.getInt('parent_id');
    final userType = prefs.getString('user_type');
    setState(() {
      _currentUserId = userId;
      _parentId = parentId;
      _userType = userType;
    });

    if (userId == null) return;

    List<Map<String, dynamic>> users = [];
    if (userType == "Aile") {
      final childrenQuery = FirebaseFirestore.instance
          .collection('users')
          .where('parent_id', isEqualTo: userId);

      final childrenSnapshot = await childrenQuery.get();
      for (final doc in childrenSnapshot.docs) {
        users.add({
          'id': doc.id,
          'name': doc.data()['appcustomer_name'] ?? doc.id,
        });
      }
    } else if (userType == "Cocuk" && parentId != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(parentId.toString()).get();
      if (doc.exists) {
        users.add({
          'id': doc.id,
          'name': doc.data()?['appcustomer_name'] ?? doc.id,
        });
      }
    }
    setState(() {
      _chatUsers = users;
      if (users.isNotEmpty) _selectedUserId = users.first['id'];
    });

    try {
      final moneyDoc = await FirebaseFirestore.instance
          .collection('user_money')
          .doc(userId.toString())
          .get();
      setState(() {
        _userMoney = (moneyDoc.data()?['money'] ?? 0).toDouble();
      });
    } catch (e) {}

    if (_selectedUserId != null) {
      _listenRoomStatus();
    }
    _listenAnyRoomActive();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _freqRoomSubscription?.cancel();
    super.dispose();
  }

  void _listenAnyRoomActive() {
    if (_currentUserId == null) return;
    List<String> listenIds = [];
    if (_userType == "Aile") {
      listenIds = _chatUsers.map((e) => e['id'].toString()).toList();
    } else if (_userType != "Aile" && _parentId != null) {
      listenIds = [_parentId.toString()];
    }
    if (listenIds.isEmpty) return;
    _freqRoomSubscription = FirebaseFirestore.instance
        .collection('active_audio_rooms')
        .where('userID', whereIn: listenIds)
        .snapshots()
        .listen((snapshot) {
      bool anyActive = snapshot.docs.any((doc) => doc['status'] == 'active');
      setState(() {
        isListening = anyActive;
      });
    });
  }

  void _listenRoomStatus() {
    if (_currentUserId == null || _selectedUserId == null) return;
    final userId = _currentUserId!;
    final otherId = _selectedUserId!;
    final roomId = "${userId}_room";

    _subscription?.cancel();

    final roomStream = FirebaseFirestore.instance
        .collection('active_audio_rooms')
        .doc(roomId)
        .snapshots();

    _subscription = roomStream.listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      final status = data['status'] as String? ?? '';
      final roomID = data['roomID'] as String? ?? '';

      String role = (roomID.split("_").last.trim() == userId.toString())
          ? "audience"
          : "broadcaster";

      if (status == 'active' && _lastRoomStatus != 'active') {
        _startNativeAgoraListening(context, role: role);
      } else if (status == 'closed' && _lastRoomStatus != 'closed') {
        _stopNativeAgoraListening(context);
      }
      _lastRoomStatus = status;
    });
  }

  Future<void> _startNativeAgoraListening(BuildContext context, {required String role}) async {
    if (_currentUserId == null || _selectedUserId == null) return;
    final userId = _currentUserId!;
    final otherId = _selectedUserId!;
    final roomId = "${userId}_room";
    const MethodChannel channel = MethodChannel('com.example.ruzgarplus/agora_service');
    try {
      await channel.invokeMethod('startAgoraListening', {
        "roomId": roomId,
        "userId": userId.toString(),
        "role": 'audience',
        "otherUserId": otherId,
        "userType":_userType,
      });
      _decreaseBalanceOnStart();
    } catch (e) {}
  }

  Future<void> _stopNativeAgoraListening(BuildContext context) async {
    if (_currentUserId == null || _selectedUserId == null) return;
    final userId = _currentUserId!;
    final otherId = _selectedUserId!;
    final roomId = "${userId}_room";
    const MethodChannel channel = MethodChannel('com.example.ruzgarplus/agora_service');
    try {
      try {
        await FirebaseFirestore.instance
            .collection('active_audio_rooms')
            .doc(roomId)
            .update({
          "status": "closed",
          "closedAt": FieldValue.serverTimestamp(),
        });
      } catch (e) {
        await FirebaseFirestore.instance
            .collection('active_audio_rooms')
            .doc(roomId)
            .set({
          "status": "closed",
          "closedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await channel.invokeMethod('stopAgoraListening');
    } catch (e) {}
  }

Future<void> _saveRoomToFirebase(BuildContext context) async {
  if (_currentUserId == null || _selectedUserId == null) {
    setState(() {
      _debugText = "Kullanıcı ID'leri null, oda kaydedilemiyor!";
    });
    return;
  }

  // 1) Kullanıcı aktif mi kontrol et
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(_selectedUserId)
      .get();

  final lastActiveTimestamp = userDoc.data()?['last_active'];

  if (lastActiveTimestamp == null) {
    _showNotActiveDialog(context);
    return;
  }

  DateTime lastActive;
  if (lastActiveTimestamp is Timestamp) {
    lastActive = lastActiveTimestamp.toDate();
  } else if (lastActiveTimestamp is int) {
    lastActive = DateTime.fromMillisecondsSinceEpoch(lastActiveTimestamp);
  } else {
    _showNotActiveDialog(context);
    return;
  }

  final now = DateTime.now();
  final diff = now.difference(lastActive).inSeconds;

  if (diff > 10) {
    _showNotActiveDialog(context);
    return;
  }

  // --- Aktif değilse return, aktifse devam ---
  final userId = _currentUserId!;
  final otherId = _selectedUserId!;
  final roomId = "${userId}_room";

  await FirebaseFirestore.instance.collection('active_audio_rooms').doc(roomId).set({
    "roomID": roomId,
    "userID": userId.toString(),
    "otherUserId": otherId,
    "status": "active",
    "createdAt": FieldValue.serverTimestamp(),
    "activeAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  setState(() {
    _debugText = "Oda kaydı oluşturuldu, Agora başlatılıyor!";
  });

  String myRole = "broadcaster";
  if (_userType == "Aile") {
    myRole = "audience";
  } else if (_userType != "Aile") {
    myRole = "broadcaster";
  }
  await _startNativeAgoraListening(context, role: myRole);

  setState(() {
    _debugText += "\nAgora başlatıldı (role: $myRole)";
  });

  await _sendLiveBroadcasterRequest();
}

void _showNotActiveDialog(BuildContext context) {
showDialog(
  context: context,
  barrierDismissible: true,
  builder: (ctx) => AlertDialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
    titlePadding: const EdgeInsets.only(top: 22, left: 22, right: 22, bottom: 0),
    title: Center(
      child: Text(
        'Kullanıcı Aktif Değil',
        style: TextStyle(
          color: Colors.red[700],
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 0.2,
        ),
        textAlign: TextAlign.center,
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(12),
          child: const Icon(
            Icons.info_outline_rounded,
            color: Colors.red,
            size: 36,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'İstediğiniz kullanıcı şu an aktif değildir!\nLütfen daha sonra tekrar deneyin.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.black87,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.red[600],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        ),
        child: const Text(
          'Tamam',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    ],
  ),
);
  setState(() {
    _debugText = "İstediğiniz kullanıcı şu an aktif değildir!";
  });
}

  Future<void> _sendLiveBroadcasterRequest() async {
    if (_currentUserId == null || _selectedUserId == null) {
      setState(() {
        _debugText += "\nAPI: Kullanıcı ID'leri null!";
      });
      return;
    }
    final userId = _currentUserId!.toString();
    final otherId = _selectedUserId!;
    final userTypes= 'Çocuk';

    final roomId = "${userId}_room";
    String role = "broadcaster";
    final payload = {
      "sender_id": userId,
      "receiver_id": otherId,
      "room_id": roomId,
      "role": role,
      "userType": userTypes,
    };

    setState(() {
      _debugText += "\nAPI: İstek gönderiliyor...";
    });

    try {
      final response = await http.post(
        Uri.parse("http://crm.ruzgarnet.site/api/sesbildirim"),
          headers: {
      'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
        body: jsonEncode(payload),
      );
    } catch (e) {}
  }

  Future<void> _decreaseBalanceOnStart() async {
    if (_currentUserId == null) return;
    final userId = _currentUserId!;
    final newMoney = (_userMoney - 0.1).clamp(0, double.infinity);
    await FirebaseFirestore.instance
        .collection('user_money')
        .doc(userId.toString())
        .set({"money": newMoney}, SetOptions(merge: true));
    setState(() {
      _userMoney = newMoney.toDouble();
    });
  }

  Future<void> _increaseBalance() async {
    if (_currentUserId == null) return;
    final userId = _currentUserId!;
    final newMoney = _userMoney + 10;
    await FirebaseFirestore.instance
        .collection('user_money')
        .doc(userId.toString())
        .set({"money": newMoney}, SetOptions(merge: true));
    setState(() {
      _userMoney = newMoney;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryPink.withOpacity(0.04),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Dinleme Ekranı'),
        elevation: 5,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryPurple.withOpacity(0.07),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    color: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          "assets/frekans.png",
                          width: 186,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // --- Modern "Dinlemeyi Başlat" Butonu (Animasyonlu ve Özel) ---
                  AnimatedListenButton(
                    isListening: isListening,
                    onPressed: () => _saveRoomToFirebase(context),
                    
                  ),
                  const SizedBox(height: 14),

                  // --- Yayın/Dinlemeyi Durdur Butonu ---
                  ElevatedButton.icon(
                    icon: const Icon(Icons.stop, size: 22, color: Colors.white),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      child: Text('Yayın/Dinlemeyi Durdur',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      minimumSize: const Size.fromHeight(46),
                      elevation: 2,
                    ),
                    onPressed: () {
                      setState(() {
                        isListening = false;
                      });
                      _stopNativeAgoraListening(context);
                    },
                  ),
                  const SizedBox(height: 18),

                  // --- Çocuk/Aile Seçme ve Bakiye Aynı Dikdörtgen Kutuda ---
     Center(
  child: Container(
  width: MediaQuery.of(context).size.width * 0.98,
    constraints: BoxConstraints(maxWidth: 500),

    decoration: BoxDecoration(
      color: Colors.brown.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.brown,
        width: 1.8,
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Çocuk/Aile seçme - YUVARLAK BORDER
        DropdownButtonFormField<String>(
          value: _selectedUserId,
          items: _chatUsers
              .map<DropdownMenuItem<String>>((user) => DropdownMenuItem<String>(
                    value: user['id'],
                    child: Text(user['name'] ?? user['id']),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _selectedUserId = v;
              _listenRoomStatus();
            });
          },
          decoration: InputDecoration(
            labelText: _userType == "Aile"
                ? "Çocuk Seç (user_id)"
                : "Aile Seç (user_id)",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: Colors.brown,
                width: 1.4,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: Colors.brown,
                width: 1.4,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: Colors.brown.shade700,
                width: 2,
              ),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          dropdownColor: Colors.white,
        ),
        const SizedBox(height: 14),
        // Bakiye kısmı (aynı şekilde)
        SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.account_balance_wallet_rounded, color: Colors.black),
      const SizedBox(width: 6),
      Text(
        "Bakiye: ",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 17,
          color: Colors.black,
        ),
      ),
      Text(
        _userMoney.toStringAsFixed(2),
        style: TextStyle(
          fontSize: 17,
          color: _userMoney > 0 ? Colors.blue[600] : Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 10),
      OutlinedButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text("Yükle"),
        onPressed: _increaseBalance,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.green[500],
          side: BorderSide(color: Colors.green, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  ),
)
      ],
    ),
  ),
),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// --- Modern Frekans Dalga Animasyonları ---
class ListeningTripleWave extends StatefulWidget {
  final bool isActive;
  const ListeningTripleWave({super.key, required this.isActive});

  @override
  State<ListeningTripleWave> createState() => _ListeningTripleWaveState();
}

class _ListeningTripleWaveState extends State<ListeningTripleWave> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    if (!widget.isActive) {
      _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant ListeningTripleWave oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 146,
      height: 56,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          double t = widget.isActive ? _controller.value : 0.0;
          return CustomPaint(
            painter: TripleWavePainter(progress: t, isActive: widget.isActive),
            size: const Size(146, 56),
          );
        },
      ),
    );
  }
}

class TripleWavePainter extends CustomPainter {
  final double progress;
  final bool isActive;
  TripleWavePainter({required this.progress, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kWaveBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;

    final amplitudes = [8.0, 15.0, 10.0];
    final yCenters = [size.height * 0.22, size.height * 0.5, size.height * 0.78];
    final phases = isActive ? [progress, progress + 0.16, progress + 0.33] : [0.0, 0.0, 0.0];
    final opacities = [0.55, 1.0, 0.55];

    for (int i = 0; i < 3; i++) {
      final path = Path();
      for (double x = 0; x <= size.width; x++) {
        final normalized = x / size.width;
        final freq = 2.2;
        final phase = 2 * pi * phases[i];
        final y = yCenters[i] +
            sin((normalized * freq * 2 * pi) + phase) *
                amplitudes[i] *
                (isActive ? (0.7 + 0.3 * sin(phase + normalized * pi)) : 1);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint..color = kWaveBlue.withOpacity(opacities[i]));
    }
  }

  @override
  bool shouldRepaint(covariant TripleWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isActive != isActive;
}

/// --- ANİMASYONLU Dinlemeyi Başlat Butonu ---
class AnimatedListenButton extends StatefulWidget {
  final bool isListening;
  final VoidCallback onPressed;
  const AnimatedListenButton({super.key, required this.isListening, required this.onPressed});

  @override
  State<AnimatedListenButton> createState() => _AnimatedListenButtonState();
}
class _AnimatedListenButtonState extends State<AnimatedListenButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.90, end: 1.15).animate(
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
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.brown.shade200,
                width: 3.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: kPrimaryPurple.withOpacity(0.12),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              icon: Icon(
                widget.isListening ? Icons.hearing : Icons.play_arrow_rounded,
                size: 28,
                color: Colors.brown[700],
              ),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                child: Text(
                  widget.isListening ? 'Dinleme Aktif' : 'Dinlemeyi Başlat',
               style: TextStyle(
  fontWeight: FontWeight.w500,
  fontSize: 19,
  letterSpacing: 0.5,
  color: Colors.black,
),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: widget.isListening ? null : widget.onPressed,
            ),
          ),
        );
      },
    );
  }
}
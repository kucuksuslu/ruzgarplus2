import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:math';

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
    // Aile ise çocuk user_id'lerini, çocuk ise ailesini ekle
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
    // Kendi veya ilişkililerle aktif odaları dinle
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

      // Rolü belirle: Odayı başlatan broadcaster, diğeri audience
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
    print("FLUTTER userType: $_userType");
    const MethodChannel channel = MethodChannel('com.example.ruzgarplus/agora_service');
    try {
      await channel.invokeMethod('startAgoraListening', {
        "roomId": roomId,
        "userId": userId.toString(),
        "role": 'audience',
        "otherUserId": otherId,
        "userType":_userType,
      
      });
      print("FLUTTER userType: $_userType");
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
    final userId = _currentUserId!;
    final otherId = _selectedUserId!;
    final roomId = "${userId}_room";

    // SADECE TEK ODA KAYDI!
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

    // --- ROL BELİRLEME ---
    // Kullanıcı tipi "Aile" ise, daima dinleyici (audience) olmalı. Yayıncı çocuk olacak.
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
     print("userType ${userTypes}");
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
        Uri.parse("http://192.168.1.196:8000/api/live-broadcaster"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      print("YANIT STATUS: ${response.statusCode}");
      print("YANIT HEADERS: ${response.headers}");
      print("YANIT BODY RAW: ${response.body.substring(0, 200)}");
    } catch (e) {
      print("HATA: $e");
    }
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: kPrimaryPink.withOpacity(0.04),
      appBar: AppBar(
        backgroundColor: kPrimaryPurple,
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
                  // --- Modern Frekans Animasyonu ---
                  const SizedBox(height: 6),
                  Card(
                    color: Colors.blue[50],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 6),
                      child: ListeningTripleWave(isActive: isListening),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // --- Modern "Dinlemeyi Başlat" Butonu ---
                  ElevatedButton.icon(
                    icon: Icon(
                      isListening ? Icons.hearing : Icons.play_arrow_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                      child: Text(
                        isListening ? 'Dinleme Aktif' : 'Dinlemeyi Başlat',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isListening ? kWaveBlue : kPrimaryPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      minimumSize: const Size.fromHeight(54),
                      shadowColor: kPrimaryPurple.withOpacity(0.20),
                      elevation: 6,
                    ),
                    onPressed: isListening
                        ? null // Zaten aktifken tekrar başlatma!
                        : () => _saveRoomToFirebase(context),
                  ),
                  const SizedBox(height: 18),
                  // --- Diğer Butonlar ve Bilgiler ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet_rounded, color: Colors.indigo[600]),
                      const SizedBox(width: 6),
                      Text("Bakiye: ",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                              color: Colors.indigo[700])),
                      Text(_userMoney.toStringAsFixed(2),
                          style: TextStyle(
                              fontSize: 17,
                              color: _userMoney > 0 ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("Yükle"),
                        onPressed: _increaseBalance,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kPrimaryPink,
                          side: BorderSide(color: kPrimaryPink, width: 1.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 22),
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                      filled: true,
                      fillColor: Colors.indigo.withOpacity(0.045),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 30),
                  Text(
                    "DEBUG LOG",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo[800],
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.indigo[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.withOpacity(0.14)),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: Text(
                        _debugText,
                        style: const TextStyle(
                          fontFamily: "monospace",
                          fontSize: 13.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
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
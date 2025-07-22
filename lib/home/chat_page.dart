import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Ana renkler
const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int? _userId;
  int? _parentId;
  String? _userType;
  String? _userName;
  List<Map<String, dynamic>> _chatUsers = [];
  int? _selectedUserId;
  bool _showEmojiPicker = false;
  final Set<String> _shownMessageDocIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserInfoAndChatUsers();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfoAndChatUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final parentId = prefs.getInt('parent_id');
    final userType = prefs.getString('user_type');
    final userName = prefs.getString('appcustomer_name');
    debugPrint('[DEBUG] Kullanıcı bilgileri yüklendi: userId=$userId, parentId=$parentId, userType=$userType, userName=$userName');
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _parentId = parentId;
      _userType = userType;
      _userName = userName;
    });
    await _loadChatUsers();
  }

  Future<void> _loadChatUsers() async {
    final firestore = FirebaseFirestore.instance;
    List<Map<String, dynamic>> users = [];
    debugPrint("[DEBUG] ChatUser yükleniyor: userType=$_userType userId=$_userId parentId=$_parentId");
    if (_userType == "Aile" && _userId != null) {
      final query = await firestore
          .collection('users')
          .where('parent_id', isEqualTo: _userId)
          .get();
      for (var doc in query.docs) {
        var data = doc.data();
        final dynamic idRaw = data['user_id'] ?? doc.id;
        data['id'] = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
        users.add(data);
      }
    } else if (_userType != "Aile" && _parentId != null) {
      final query = await firestore
          .collection('users')
          .where('user_id', isEqualTo: _parentId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        var data = query.docs.first.data();
        final dynamic idRaw = data['user_id'] ?? query.docs.first.id;
        data['id'] = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
        users.add(data);
      }
    }
    debugPrint('[DEBUG] Yüklenen chatUsers: $users');
    if (!mounted) return;
    setState(() {
      _chatUsers = users;
      if (users.isNotEmpty) {
        _selectedUserId = users.first['id'];
      }
    });
  }

  String getRoomId(int userIdA, int userIdB) {
    final sorted = [userIdA, userIdB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  void _sendMessage() async {
    debugPrint('[DEBUG] _sendMessage çağrıldı!');
    final text = _controller.text.trim();
    debugPrint('[DEBUG] Mesaj hazırlanıyor: "$text"');
    if (text.isEmpty || _selectedUserId == null || _userId == _selectedUserId) {
      debugPrint('[DEBUG] Mesaj gönderme engellendi: text boş, veya kullanıcı seçilmemiş ya da kendine mesaj atıyor.');
      if (_selectedUserId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen bir kişi seçin!')),
        );
      }
      return;
    }

    // Kullanıcılar arası izin kontrolü
    if (_userType == "Aile" && _chatUsers.every((u) => u['id'] != _selectedUserId)) {
      debugPrint('[DEBUG] Aile, olmayan bir kullanıcıya mesaj atmaya çalışıyor!');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu kullanıcıya mesaj atamazsınız!')),
      );
      return;
    }
    if (_userType == "Cocuk" && _selectedUserId != _parentId) {
      debugPrint('[DEBUG] Çocuk, ailesi dışında mesaj göndermeye çalışıyor!');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sadece aileniz ile sohbet edebilirsiniz!')),
      );
      return;
    }

    final roomId = getRoomId(_userId!, _selectedUserId!);
    debugPrint('[DEBUG] Oda ID: $roomId');
    final docRef = _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .doc();

    final messageData = {
      'doc': docRef.id,
      'sender_id': _userId,
      'receiver_id': _selectedUserId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'is_read': false,
      'sender_name': _userName ?? '',
    };

    await docRef.set(messageData);
    debugPrint('[DEBUG] Firestore mesajı kaydedildi: $messageData');

    try {
      debugPrint('[DEBUG] API çağrısı başlatılıyor');
      final response = await http.post(
        Uri.parse("http://crm.ruzgarnet.site/api/sendMessageNotification"),
            headers: {
      'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
        body: jsonEncode({
          'sender_id': _userId,
          'receiver_id': _selectedUserId,
          'sender_name': _userName ?? '',
          'text': text,
        }),
      );
      debugPrint('[DEBUG] API yanıtı: ${response.statusCode} - ${response.body}');
      if (!mounted) return;
   if (response.statusCode == 200) {
  debugPrint('[DEBUG] API yanıtı: ${response.statusCode} - ${response.body}');
 
} else {
  debugPrint('[DEBUG] API yanıtı: ${response.statusCode} - ${response.body}');
  
}
    } catch (e) {
      debugPrint('[DEBUG] API hata: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('API hata: $e')),
      );
    }

    if (!mounted) return;
    _controller.clear();
  }

  void _onEmojiSelected(Emoji emoji) {
    _controller
      ..text += emoji.emoji
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    setState(() {});
  }

  void _toggleEmojiPicker() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
  }

  Future<void> _markMessageAsRead(String roomId, String docId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(roomId)
          .collection('messages')
          .doc(docId)
          .update({'is_read': true});
    } catch (e) {
      debugPrint('[DEBUG] Mesaj okundu işaretlenirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Sohbet'),
          backgroundColor: kPrimaryPurple,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            "Kullanıcı kimliği alınamadı!\n\nLütfen giriş yaptığınızdan ve user_id'nin SharedPreferences'da olduğundan emin olun.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.red),
          ),
        ),
      );
    }

    final dropdownValue = _chatUsers.any((u) => u['id'] == _selectedUserId)
        ? _selectedUserId
        : (_chatUsers.isNotEmpty
            ? _chatUsers.first['id']
            : null);

    if (_selectedUserId != dropdownValue && dropdownValue != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedUserId = dropdownValue;
          });
        }
      });
    }

    final roomId = (_userId != null && dropdownValue != null)
        ? getRoomId(_userId!, dropdownValue)
        : null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Sohbet"),
        elevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // --- ARKAPLAN RESMİ ---
            Positioned.fill(
              child: Image.asset(
                "assets/denemes3.png",
                fit: BoxFit.cover,
              ),
            ),
            // --- ÜSTTEKİ ANA CHAT WIDGET'I ---
            Column(
              children: [
                // Kişi seçimi
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 10.0),
                  child: Row(
                    children: [
                      const Text(
                        "Kişi seç: ",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      const SizedBox(width: 10),
                      _chatUsers.isEmpty
                          ? const Text("Sohbet için kişi yok.", style: TextStyle(color: Colors.black))
                          : Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFBDA8AC),
                                    Color(0xFFF8F6F6),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: Colors.black, width: 2),
                                borderRadius: BorderRadius.circular(38),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: dropdownValue,
                                  icon: Icon(Icons.arrow_drop_down, color: Colors.black),
                                  items: _chatUsers
                                      .map<DropdownMenuItem<int>>((u) => DropdownMenuItem<int>(
                                            value: u['id'],
                                            child: Text(
                                              u['appcustomer_name'] ?? "Kullanıcı",
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedUserId = val);
                                  },
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                // Mesajlar
                Expanded(
                  child: (roomId == null)
                      ? const Center(
                          child: Text(
                            "Sohbet için kişi yok.",
                            style: TextStyle(color: Colors.black, fontSize: 16),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: kPrimaryPurple.withOpacity(0.05),
                                blurRadius: 18,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('chats')
                                .doc(roomId)
                                .collection('messages')
                                .orderBy('timestamp', descending: true)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final docs = snapshot.data!.docs.toList();

                              return ListView.builder(
                                reverse: true,
                                itemCount: docs.length,
                                itemBuilder: (context, index) {
                                  final data = docs[index].data() as Map<String, dynamic>;
                                  final senderId = data['sender_id'];
                                  final receiverId = data['receiver_id'];
                                  final text = data['text'] ?? '';
                                  final isMe = senderId == _userId;
                                  final isRead = data['is_read'] == true;
                                  final senderName = data['sender_name'] ?? '';
                                  final docId = data['doc'] ?? docs[index].id;

                                  // Mesajı okundu olarak işaretle (sadece alıcıysak, okundu değilse)
                                  if (receiverId == _userId && !isRead && !_shownMessageDocIds.contains(docId)) {
                                    _shownMessageDocIds.add(docId);
                                    _markMessageAsRead(roomId, docId);
                                  }

                                  return Align(
                                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 14),
                                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      decoration: BoxDecoration(
                                        color: const Color(0x9F120000),
                                        borderRadius: BorderRadius.circular(38),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.07),
                                            blurRadius: 7,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                senderName,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              if (isMe)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 7.0),
                                                  child: Icon(
                                                    Icons.done_all,
                                                    color: isRead ? Colors.blue : Colors.white,
                                                    size: 18,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            text,
                                            style: const TextStyle(
                                              fontSize: 15.5,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                ),
                const Divider(height: 1),
                // Mesaj kutusu ve butonlar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    border: Border(
                      top: BorderSide(color: kPrimaryPurple.withOpacity(0.13), width: 2),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.emoji_emotions, color: Color(0xFFFF1585), size: 28),
                        onPressed: _chatUsers.isNotEmpty && _selectedUserId != _userId
                            ? _toggleEmojiPicker
                            : null,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          decoration: InputDecoration(
                            hintText: _chatUsers.isEmpty
                                ? 'Sohbet için kişi yok'
                                : (_selectedUserId == _userId
                                    ? 'Kendinize mesaj atamazsınız'
                                    : 'Mesajınızı yazın...'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            filled: true,
                            fillColor: Color(0xFFF8F6F6),
                          ),
                          enabled: _chatUsers.isNotEmpty && _selectedUserId != _userId,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send, color: Colors.brown),
                        onPressed: _chatUsers.isNotEmpty && _selectedUserId != _userId
                            ? _sendMessage
                            : null,
                      ),
                    ],
                  ),
                ),
                if (_showEmojiPicker)
                  SizedBox(
                    height: 310,
                    child: EmojiPicker(
                      onEmojiSelected: (category, emoji) {
                        _onEmojiSelected(emoji);
                      },
                      config: const Config(
                        height: 256,
                        checkPlatformCompatibility: true,
                        emojiViewConfig: EmojiViewConfig(
                          emojiSizeMax: 28 * 1.5,
                          columns: 7,
                          verticalSpacing: 0,
                          horizontalSpacing: 0,
                        ),
                        skinToneConfig: SkinToneConfig(),
                        categoryViewConfig: CategoryViewConfig(),
                        bottomActionBarConfig: BottomActionBarConfig(),
                        searchViewConfig: SearchViewConfig(),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
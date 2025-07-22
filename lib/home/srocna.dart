import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:location/location.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);

// MapTiler API anahtarınızı buraya yazın!
const String mapTilerKey = '9mDxXPWnyEAbexVqNUJs';

class SrocniyPage extends StatefulWidget {
  const SrocniyPage({Key? key}) : super(key: key);

  @override
  State<SrocniyPage> createState() => _SrocniyPageState();
}

class _SrocniyPageState extends State<SrocniyPage> {
  bool _isSendingSms = false;
  bool _isCalling = false;
  bool _isSendingWhatsapp = false;
  bool _isSendingAlarm = false;
  LatLng? _currentLatLng;
  String? _locationString;
  bool _isLoadingLocation = true;
  List<String> _emergencyNumbers = [];

  List<Map<String, dynamic>> _users = [];
  int? _userId;
  String? _userType;

  @override
  void initState() {
    super.initState();
    _fetchLocation();
    _loadNumbers();
    _loadUserInfoAndUsers();
  }

  Future<void> _loadUserInfoAndUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    final userType = prefs.getString('user_type');
    setState(() {
      _userId = userId;
      _userType = userType;
    });
    if (userId != null && userType != null) {
      await _loadUsersFromFirestore(userId, userType);
    }
  }

  Future<void> _loadUsersFromFirestore(int userId, String userType) async {
    final firestore = FirebaseFirestore.instance;
    List<Map<String, dynamic>> users = [];

    if (userType == "Aile") {
      final ownDocQuery = await firestore
          .collection('users')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();
      if (ownDocQuery.docs.isNotEmpty) {
        final doc = ownDocQuery.docs.first;
        final data = doc.data();
        users.add({
          'id': doc.id,
          'appcustomer_name': data['appcustomer_name'] ?? '',
          'user_id': data['user_id'],
          'user_type': data['user_type'],
          'app_phone': data['app_phone'] ?? '',
        });
      }
      final childrenQuery = await firestore
          .collection('users')
          .where('parent_id', isEqualTo: userId)
          .get();
      for (final doc in childrenQuery.docs) {
        final data = doc.data();
        users.add({
          'id': doc.id,
          'appcustomer_name': data['appcustomer_name'] ?? '',
          'user_id': data['user_id'],
          'user_type': data['user_type'],
          'app_phone': data['app_phone'] ?? '',
        });
      }
    } else {
      final ownDocQuery = await firestore
          .collection('users')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();
      if (ownDocQuery.docs.isNotEmpty) {
        final doc = ownDocQuery.docs.first;
        final data = doc.data();
        users.add({
          'id': doc.id,
          'appcustomer_name': data['appcustomer_name'] ?? '',
          'user_id': data['user_id'],
          'user_type': data['user_type'],
          'app_phone': data['app_phone'] ?? '',
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _users = users;
    });
  }

  Future<void> _loadNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emergencyNumbers = prefs.getStringList('emergency_numbers') ?? [''];
    });
  }

  Future<void> _saveNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_numbers', _emergencyNumbers);
  }

  Future<void> _addNumber() async {
    final controller = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Numara Ekle'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '+905XXXXXXXXX'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryPurple),
            onPressed: () {
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Ekle', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (added != null && added.isNotEmpty && !_emergencyNumbers.contains(added)) {
      setState(() => _emergencyNumbers.add(added));
      await _saveNumbers();
    }
  }

  Future<void> _editNumber(int idx) async {
    final controller = TextEditingController(text: _emergencyNumbers[idx]);
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Numarayı Düzenle'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryPurple),
            onPressed: () {
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Kaydet', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (edited != null && edited.isNotEmpty) {
      setState(() => _emergencyNumbers[idx] = edited);
      await _saveNumbers();
    }
  }

  Future<void> _removeNumber(int idx) async {
    setState(() => _emergencyNumbers.removeAt(idx));
    await _saveNumbers();
  }

  Future<void> _fetchLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      Location location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          setState(() {
            _locationString = "Konum servisi kapalı!";
            _isLoadingLocation = false;
          });
          return;
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          setState(() {
            _locationString = "Konum izni verilmedi!";
            _isLoadingLocation = false;
          });
          return;
        }
      }

      LocationData loc = await location.getLocation();
      final latLng = LatLng(loc.latitude ?? 0.0, loc.longitude ?? 0.0);
      setState(() {
        _currentLatLng = latLng;
        _locationString = "https://maps.google.com/?q=${latLng.latitude},${latLng.longitude}";
        _isLoadingLocation = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationString = "Konum alınamadı!";
        _isLoadingLocation = false;
      });
    }
  }

  Future<void> sendSms(String message, List<String> recipients) async {
    final uri = Uri(
      scheme: 'sms',
      path: recipients.join(','),
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("SMS uygulaması açılamadı!"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleSendWhatsapp() async {
    setState(() => _isSendingWhatsapp = true);

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final selectedNumbers = <String>{};
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text("WhatsApp ile mesaj gönderilecek numaralar"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _emergencyNumbers.map((num) {
                    return CheckboxListTile(
                      value: selectedNumbers.contains(num),
                      title: Text(num),
                      activeColor: kPrimaryPurple,
                      onChanged: (val) {
                        setStateDialog(() {
                          if (val == true) {
                            selectedNumbers.add(num);
                          } else {
                            selectedNumbers.remove(num);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimaryPink),
                  onPressed: () {
                    Navigator.pop(ctx, selectedNumbers.toList());
                  },
                  child: const Text("Gönder", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      final message = "ACİL DURUM! Lütfen yardım edin. Konumum: ${_locationString ?? ''}";
      for (final number in selected) {
        final cleanedNumber = number.replaceAll(RegExp(r'^\+'), '').replaceAll(RegExp(r'^0+'), '');
        final url = Uri.parse('https://wa.me/$cleanedNumber?text=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
          await Future.delayed(const Duration(seconds: 2));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$number için WhatsApp açılamadı!"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("WhatsApp ile acil mesajlar gönderildi!"),
            backgroundColor: kPrimaryPurple,
          ),
        );
      }
    }
    setState(() => _isSendingWhatsapp = false);
  }

  Future<void> _handleSendLocationSms() async {
    setState(() => _isSendingSms = true);

    if (_emergencyNumbers.isNotEmpty) {
      final message = "ACİL DURUM! Lütfen yardım edin. Konumum: ${_locationString ?? ''}";
      await sendSms(message, _emergencyNumbers);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("SMS ekranı açıldı!"),
          backgroundColor: kPrimaryPurple,
        ));
      }
    }
    setState(() => _isSendingSms = false);
  }

  Future<void> _handleEmergencyCall() async {
    setState(() => _isCalling = true);

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final selectedNumbers = <String>{};
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text("Aranacak Numaralar"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: _emergencyNumbers.map((num) {
                    return CheckboxListTile(
                      value: selectedNumbers.contains(num),
                      title: Text(num),
                      activeColor: kPrimaryPurple,
                      onChanged: (val) {
                        setStateDialog(() {
                          if (val == true) {
                            selectedNumbers.add(num);
                          } else {
                            selectedNumbers.remove(num);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimaryPink),
                  onPressed: () {
                    Navigator.pop(ctx, selectedNumbers.toList());
                  },
                  child: const Text("Ara", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      for (final num in selected) {
        await launchUrl(Uri.parse("tel:$num"));
        await Future.delayed(const Duration(seconds: 2));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text("Acil durum aramaları başlatıldı!"),
          backgroundColor: kPrimaryPink,
        ));
      }
    }
    setState(() => _isCalling = false);
  }

  Future<void> _handleAlarmButton() async {
    setState(() => _isSendingAlarm = true);

    final List<Map<String, dynamic>> selectableUsers = (_userType == "Aile")
        ? _users.where((u) => u['user_type'] != "Aile").toList()
        : _users;

    String? tempSelectedId = selectableUsers.isNotEmpty && selectableUsers.first['id'] != null
        ? selectableUsers.first['id'] as String
        : null;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text("Alarm için çocuk seç"),
              content: selectableUsers.isEmpty
                  ? const Text("Hiç çocuk bulunamadı!")
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: tempSelectedId,
                      items: selectableUsers
                          .where((f) => f['id'] != null)
                          .map((f) => DropdownMenuItem<String>(
                                value: f['id'] as String,
                                child: Text(f['appcustomer_name'] ?? ''),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          tempSelectedId = val;
                        });
                      },
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("İptal"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: kPrimaryPink),
                  onPressed: tempSelectedId == null
                      ? null
                      : () {
                          final selectedUser = selectableUsers.firstWhere(
                              (f) => f['id'] == tempSelectedId,
                              orElse: () => {});
                          Navigator.pop(ctx, selectedUser);
                        },
                  child: const Text("Alarm Gönder", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && selected.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('http://crm.ruzgarnet.site/api/sendappalert'),
              headers: {
      'Authorization': 'Basic cnV6Z2FybmV0Oksucy5zLjUxNTE1MQ==',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
          body: jsonEncode({
            "trigger_user_id": _userId,
            "target_user_id": selected['user_id'],
          }),
        );
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("${selected['appcustomer_name']} kişisine alarm bildirimi gönderildi!"),
            backgroundColor: kPrimaryPink,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Alarm gönderilemedi: ${response.body}"),
            backgroundColor: Colors.red,
          ));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("İstek hatası: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
    setState(() => _isSendingAlarm = false);
  }

  Widget _buildEmergencyCallButtons() {
return Padding(
  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
  children: [
  for (final item in [
    {'icon': '🏥', 'label': '112', 'url': "tel:112"},
    {'icon': '👮‍♀️', 'label': '155', 'url': "tel:155"},
    {'icon': '🚔', 'label': '156', 'url': "tel:156"},
  ])
    Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white, 
        shape: BoxShape.circle,
        border: Border.all(color: Colors.red, width: 1.5),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: const CircleBorder(
            side: BorderSide(color: Colors.red, width: 1.5),
          ),
          elevation: 0,
          padding: EdgeInsets.zero,
        ),
        onPressed: () => launchUrl(Uri.parse(item['url'] as String)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            item['icon'] is IconData
              ? Icon(item['icon'] as IconData, color: Colors.black, size: 28)
              : Text(item['icon'] as String, style: TextStyle(fontSize: 28)),
            SizedBox(height: 4),
            Text(
              item['label'] as String,
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
]

  ),
);
  }

  Widget _numberListSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            ListTile(
              title: Text(
                "Acil Durum Numaraları",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
          trailing: InkWell(
  onTap: _addNumber,
  borderRadius: BorderRadius.circular(32),
  child: CircleAvatar(
    backgroundColor: Colors.black, // veya istediğin renk
    radius: 20,
    child: Icon(Icons.add, color: Colors.white),
  ),
),
            ),
            ..._emergencyNumbers.asMap().entries.map((entry) {
              final idx = entry.key;
              final num = entry.value;
              return ListTile(
                title: Text(num, style: TextStyle(color: Colors.red)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                 children: [
  InkWell(
    onTap: () => _editNumber(idx),
    borderRadius: BorderRadius.circular(32),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black, // Siyah arkaplan
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.edit, color: Colors.white), // Beyaz ikon
    ),
  ),
  SizedBox(width: 8), // Butonlar arası boşluk isteğe bağlı
  InkWell(
    onTap: () => _removeNumber(idx),
    borderRadius: BorderRadius.circular(32),
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black, // Siyah arkaplan
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.delete, color: Colors.white), // Beyaz ikon
    ),
  ),
],
                ),
              );
            })
          ],
        ),
      ),
    );
  }

Widget _modernActionButton({
  required String label,
  required Color color,
  required VoidCallback? onPressed,
  bool loading = false,
  double borderRadius = 16,
  Widget? iconWidget, // <-- yeni parametre
}) {
  return ElevatedButton.icon(
    icon: iconWidget ??
        Icon(Icons.circle, size: 28, color: Colors.black), // default icon
    label: loading
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)),
          )
        : Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.black),
          ),
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
      elevation: 8,
    ),
    onPressed: loading ? null : onPressed,
  );
}


  @override

  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPrimaryPurple.withOpacity(0.05),
      appBar: PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
          colors: [
  Color(0xFF7B5E57), // Daha koyu kahverengi
  Color(0xFFD7CCC8), // Açık bej-kahve
],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
        ),
        child: AppBar(
          title: const Text("Acil Durum Çağrıları"),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
          ),
        ),
      ),
    ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (_isLoadingLocation)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_currentLatLng != null)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.brown, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryPurple.withOpacity(0.07),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: _currentLatLng!,
                        initialZoom: 15,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerKey',
                          userAgentPackageName: 'com.example.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              width: 60,
                              height: 60,
                              point: _currentLatLng!,
                              child: Icon(Icons.location_pin, color: kPrimaryPink, size: 48),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text("Konum alınamadı!")),
                ),
              _buildEmergencyCallButtons(),
              _numberListSection(),

              // --- Elliptic Action Buttons inside a Card ---
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 24),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 12),
                    child: Column(
                      children: [
                        _modernActionButton(
                         iconWidget: Icon(Icons.sms,color:Colors.white),
                          label: 'Konumu SMS Gönder',
                          color: Color(0xFF8D6E63).withOpacity(0.15),
                          loading: _isSendingSms,
                          onPressed: _handleSendLocationSms,
                          borderRadius: 32, // <-- eklendi!
                        ),
                        const SizedBox(height: 16),
                     _modernActionButton(
  label: 'Konumu WhatsApp\'tan Gönder',
  color: Color(0xFF8D6E63).withOpacity(0.15),
  loading: _isSendingWhatsapp,
  onPressed: _handleSendWhatsapp,
  borderRadius: 32,
  iconWidget: Image.asset(
    'assets/bariswhatsapp.png',
    width: 28,
    height: 28,
  ),
),
                        const SizedBox(height: 16),
                        _modernActionButton(
                           iconWidget: Icon(Icons.warning_amber_rounded,color:Colors.red),
                          label: 'ACİL DURUM! Hepsini Ara',
                          color: Color(0xFF8D6E63).withOpacity(0.15),
                          loading: _isCalling,
                          onPressed: _handleEmergencyCall,
                          borderRadius: 32,
                        ),
                        const SizedBox(height: 16),
                        _modernActionButton(
                           iconWidget: Icon(Icons.alarm,color:Colors.white),
                          label: 'ACİL DURUM ALARMI!',
                           color: Colors.red,
                          loading: _isSendingAlarm,
                          onPressed: _handleAlarmButton,
                          borderRadius: 32,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
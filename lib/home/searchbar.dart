import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

const Color primaryColor = Color(0xFF5e17eb);
const Color accentColor = Color(0xFFff1585);
const Color bgColor = Color(0xFFf7f5fb);
const Color cardBg = Color(0xFFe6e3f5);
const Color areaBorderColor = primaryColor;
const double cardElevation = 4.0;

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  MapController mapController = MapController();

  List<Marker> markers = [];
  List<Map<String, dynamic>> allLocations = [];
  LatLng? myPosition;
  List<bool> showBubbleList = [];
  bool showMyBubble = true;

  int? _userId;
  int? _parentId;
  String? _userType;
  String? _userName;

  LatLng? _areaCenter;
  double? _areaRadiusMeter;
  bool _alarmActive = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _firestoreLocationSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _areaLimitSubscription;

  List<Map<String, dynamic>> _childCurrentLocations = [];
  Map<String, String> _addressCache = {};

  bool _disposed = false;

  static const String locationIqApiKey = 'pk.fa04e03ad4bc91e7e95e2d5e33fd249b';
  static const String mapTilerKey = '9mDxXPWnyEAbexVqNUJs';

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.13).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _colorAnimation = TweenSequence<Color?>(
      [
        TweenSequenceItem(
          tween: ColorTween(begin: accentColor, end: primaryColor),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: primaryColor, end: Colors.greenAccent),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.greenAccent, end: Colors.orange),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.orange, end: accentColor),
          weight: 1,
        ),
      ],
    ).animate(_animationController);

    _loadUserInfo().then((_) async {
      if (_userType == 'Aile' && _userId != null) {
        await _loadChildrenCurrentLocations(_userId!);
      }
      _listenLocations();
      _listenAreaLimit();
      _getCurrentLocation();
      if (_userType == 'Aile') {
        _startPositionStream();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _firestoreLocationSubscription?.cancel();
    _positionStreamSubscription?.cancel();
    _areaLimitSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    setState(() {
      _userId = prefs.getInt('user_id');
      _parentId = prefs.getInt('parent_id');
      _userType = prefs.getString('user_type');
      _userName = prefs.getString('appcustomer_name');
    });
  }

  void _listenAreaLimit() {
    final areaLimitId = _userType == 'Aile' ? _userId?.toString() : _parentId?.toString();
    if (areaLimitId == null) return;
    _areaLimitSubscription?.cancel();
    _areaLimitSubscription = firestore
        .collection('area_limits')
        .doc(areaLimitId)
        .snapshots()
        .listen((doc) {
      if (_disposed) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (!mounted) return;
        setState(() {
          _areaCenter = LatLng(data['center_lat'], data['center_lng']);
          _areaRadiusMeter = (data['radius_m'] as num).toDouble();
          _alarmActive = true;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _areaCenter = null;
          _areaRadiusMeter = null;
          _alarmActive = false;
        });
      }
    });
  }

  void _listenLocations() {
    _firestoreLocationSubscription?.cancel();
    if (_userId == null || _userType == null) return;

    if (_userType == 'Aile') {
      _firestoreLocationSubscription = firestore
          .collection('user_locations')
          .where('parent_id', isEqualTo: _userId)
          .snapshots()
          .listen((snapshot) {
        if (_disposed) return;
        List<Map<String, dynamic>> locs = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = data['latitude']?.toDouble();
          final lng = data['longitude']?.toDouble();
          if (lat != null && lng != null) {
            locs.add({
              'id': data['user_id'],
              'appcustomer_name': data['appcustomer_name'] ?? data['name'] ?? '',
              'position': LatLng(lat, lng),
              'user_type': data['user_type'],
              'profile_image_url': data['profile_image_url'],
              'latitude': lat,
              'longitude': lng,
              'timestamp': data['timestamp'],
            });
          }
        }
        if (!mounted) return;
        setState(() {
          allLocations = locs;
          _childCurrentLocations = locs;
          showBubbleList = List.generate(locs.length, (index) => true);
          _updateMarkers();
        });
      });
    } else if (_userType == 'Çocuk' && _userId != null) {
      _firestoreLocationSubscription = firestore
          .collection('user_locations')
          .where('user_id', isEqualTo: _userId)
          .snapshots()
          .listen((snapshot) {
        if (_disposed) return;
        List<Map<String, dynamic>> locs = [];
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final lat = data['latitude']?.toDouble();
          final lng = data['longitude']?.toDouble();
          if (lat != null && lng != null) {
            locs.add({
              'id': data['user_id'],
              'appcustomer_name': data['appcustomer_name'] ?? data['name'] ?? '',
              'position': LatLng(lat, lng),
              'user_type': data['user_type'],
              'profile_image_url': data['profile_image_url'],
              'latitude': lat,
              'longitude': lng,
              'timestamp': data['timestamp'],
            });
          }
        }
        if (!mounted) return;
        setState(() {
          allLocations = locs;
          showBubbleList = List.generate(locs.length, (index) => true);
          _updateMarkers();
        });
      });
    }

    firestore
        .collection('user_locations')
        .doc(_userId.toString())
        .snapshots()
        .listen((doc) {
      if (_disposed) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final lat = data['latitude']?.toDouble();
        final lng = data['longitude']?.toDouble();
        if (lat != null && lng != null) {
          if (!mounted) return;
          setState(() {
            myPosition = LatLng(lat, lng);
            _updateMarkers();
            mapController.move(myPosition!, 15.0);
          });
          _checkIfOutsideAreaLimit();
        }
      }
    });
  }

  Future<String> getShortAddress(double lat, double lng, {int retryCount = 0}) async {
    final key = '$lat,$lng';
    if (_addressCache.containsKey(key)) {
      return _addressCache[key]!;
    }
    try {
      final url = Uri.parse(
        'https://us1.locationiq.com/v1/reverse.php?key=$locationIqApiKey&lat=$lat&lon=$lng&format=json'
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['display_name']?.toString() ?? '';
        if (address.isNotEmpty && address != "Adres getirilemedi") {
          _addressCache[key] = address;
          return address;
        }
      }
    } catch (e) {}
    if (retryCount < 2) {
      await Future.delayed(const Duration(seconds: 2));
      return await getShortAddress(lat, lng, retryCount: retryCount + 1);
    }
    _addressCache[key] = "Adres getirilemedi";
    return "Adres getirilemedi";
  }

  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "";
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else if (timestamp is String) {
      date = DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return timestamp.toString();
    }
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  Future<void> _loadChildrenCurrentLocations(int aileUserId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('user_locations')
        .where('parent_id', isEqualTo: aileUserId)
        .get();

    final List<Map<String, dynamic>> children = [];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final lat = data['latitude']?.toDouble();
      final lng = data['longitude']?.toDouble();
      if (lat == null || lng == null) continue;
      children.add({
        'user_id': data['user_id'],
        'appcustomer_name': data['appcustomer_name'] ?? data['name'] ?? '',
        'latitude': lat,
        'longitude': lng,
        'timestamp': data['timestamp'],
        'profile_image_url': data['profile_image_url'],
      });
    }
    if (_disposed) return;
    setState(() {
      _childCurrentLocations = children;
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position =
          await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      if (!mounted) return;
      setState(() {
        myPosition = LatLng(position.latitude, position.longitude);
        _updateMarkers();
      });

      mapController.move(myPosition!, 15.0);
      _checkIfOutsideAreaLimit();
    } catch (e) {}
  }

  void _startPositionStream() async {
    if (_userType != 'Çocuk' || _userId == null) return;
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;
    if (_positionStreamSubscription != null &&
        !_positionStreamSubscription!.isPaused) return;

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (_disposed) return;
      await firestore.collection('user_locations').doc(_userId.toString()).set({
        'user_id': _userId,
        'user_type': 'Çocuk',
        'parent_id': _parentId,
        'appcustomer_name': _userName ?? '',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        myPosition = LatLng(position.latitude, position.longitude);
        _updateMarkers();
        mapController.move(myPosition!, 15.0);
      });
      _checkIfOutsideAreaLimit();
    });
  }

  double _distanceBetween(LatLng p1, LatLng p2) {
    const earthRadius = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * pi / 180.0;
    final dLng = (p2.longitude - p1.longitude) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * pi / 180.0) *
            cos(p2.latitude * pi / 180.0) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  void _checkIfOutsideAreaLimit() {
    if (_userType == 'Çocuk' &&
        _areaCenter != null &&
        _areaRadiusMeter != null &&
        myPosition != null) {
      final double distance = _distanceBetween(myPosition!, _areaCenter!);
      if (distance > _areaRadiusMeter!) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Dikkat! Alan sınırının dışındasın!'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        );
      }
    }
  }

  Future<void> _showRadiusSelectionDialog(
      BuildContext context, LatLng center) async {
    double tempArea = 8.0;
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Alan Seç (km²)', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, setStateDialog) => Column(
                  children: [
                    Slider(
                      min: 0.5,
                      max: 50,
                      divisions: 99,
                      value: tempArea,
                      label: '${tempArea.toStringAsFixed(1)} km²',
                      activeColor: accentColor,
                      inactiveColor: accentColor.withOpacity(0.2),
                      onChanged: (v) {
                        setStateDialog(() {
                          tempArea = v;
                        });
                      },
                    ),
                    Text('${tempArea.toStringAsFixed(1)} km²', style: TextStyle(color: primaryColor)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                double areaM2 = tempArea * 1000000;
                double radiusMeter = sqrt(areaM2 / pi);
                await firestore
                    .collection('area_limits')
                    .doc(_userId.toString())
                    .set({
                  'center_lat': center.latitude,
                  'center_lng': center.longitude,
                  'radius_m': radiusMeter,
                  'timestamp': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  void _updateMarkers() {
    List<Marker> newMarkers = [];
    for (var i = 0; i < allLocations.length; i++) {
      var loc = allLocations[i];
      final profileImageUrl = loc['profile_image_url'];

      newMarkers.add(
        Marker(
          key: ValueKey('marker_$i'),
          point: loc['position'],
          width: 160,
          height: 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // BALONCUK: TAM ALTINDA ve küçük
              Positioned(
                top: 56,
                left: 30,
                right: 30,
                child: Visibility(
                  visible: showBubbleList.length > i && showBubbleList[i],
                  child: AnimatedOpacity(
                    opacity: showBubbleList.length > i && showBubbleList[i] ? 1 : 0,
                    duration: const Duration(milliseconds: 80),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          showBubbleList[i] = false;
                        });
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: accentColor.withOpacity(0.4), width: 0.6),
                          boxShadow: [],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, color: accentColor.withOpacity(0.6), size: 13),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                loc['appcustomer_name'] ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // İKON: ORTADA
              Positioned(
                top: 20,
                left: 62, // (160-36)/2
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      showBubbleList[i] = !showBubbleList[i];
                    });
                  },
                  child: profileImageUrl != null && profileImageUrl.toString().isNotEmpty
                      ? Material(
                          elevation: cardElevation,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: CircleAvatar(
                            backgroundImage: NetworkImage(profileImageUrl),
                            radius: 15,
                            backgroundColor: Colors.white,
                          ),
                        )
                      : Icon(
                          Icons.person_pin_circle,
                          color: accentColor.withOpacity(0.7),
                          size: 30,
                          shadows: [],
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // KENDİ KONUMUN
    if (myPosition != null) {
      newMarkers.add(
        Marker(
          key: const ValueKey('marker_myself'),
          point: myPosition!,
          width: 160,
          height: 180,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // BALONCUK: TAM ÜSTÜNDE ve küçük
              Positioned(
                top: 0,
                left: 36,
                right: 36,
                child: Visibility(
                  visible: showMyBubble,
                  child: AnimatedOpacity(
                    opacity: showMyBubble ? 1 : 0,
                    duration: const Duration(milliseconds: 80),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          showMyBubble = false;
                        });
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 90),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accentColor.withOpacity(0.3), width: 0.5),
                          boxShadow: [],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.my_location, color: accentColor.withOpacity(0.65), size: 12),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                "Konumum",
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // İKON: ORTADA
              Positioned(
                top: 22,
                left: 62,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      showMyBubble = !showMyBubble;
                    });
                  },
                  child: Icon(
                    Icons.location_on,
                    color: accentColor.withOpacity(0.7),
                    size: 30,
                    shadows: [],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    setState(() {
      markers = newMarkers;
    });
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: bgColor,
    appBar: PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight + 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF8D6E63).withOpacity(0.15),
          border: Border.all(
            color: const Color(0xFF6B5048),
            width: 3,
          ),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
        ),
        child: AppBar(
          title: Row(
            children: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) => Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Icon(
                    Icons.search,
                    color: Colors.black,
                    size: 32,
                    shadows: [
                      Shadow(
                        blurRadius: 16,
                        color: _colorAnimation.value?.withOpacity(0.4) ?? accentColor,
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Konum Bul'),
              const Spacer(),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) => Transform.scale(
                  scale: _scaleAnimation.value * 0.9,
                  child: const Icon(
                    Icons.wifi_tethering,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(26),
              bottomRight: Radius.circular(26),
            ),
          ),
        ),
      ),
    ),
    body: Column(
      children: [
        // ÇOCUKLARIN GÜNCEL KONUMU ALANI (HARİTANIN ÜSTÜNDE SABİT)
        if (_userType == 'Aile' && _childCurrentLocations.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(8, 10, 8, 2),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.96),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.09),
                  blurRadius: 18,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 2, bottom: 2),
                  child: Text(
                    'Çocukların Güncel Konumları',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: Colors.black),
                  ),
                ),
                const SizedBox(height: 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _childCurrentLocations
                        .map(
                          (child) => AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, childWidget) => Transform.scale(
                              scale: _scaleAnimation.value,
                             child: Card(
  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
  elevation: cardElevation,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Container(
    width: 270,
    // Yükseklik sabitlemek için (gerekirse) aşağıdaki satırı ekleyebilirsin:
    // constraints: BoxConstraints(maxHeight: 120),
    decoration: BoxDecoration(
      color: const Color(0xFF8D6E63).withOpacity(0.12),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.all(6), // padding'i küçült
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        (child["profile_image_url"] != null &&
                child["profile_image_url"].toString().isNotEmpty)
            ? CircleAvatar(
                backgroundImage: NetworkImage(child["profile_image_url"]),
                radius: 14,
                backgroundColor: Colors.white,
              )
            : const CircleAvatar(
                child: Icon(Icons.person, size: 16),
                backgroundColor: Colors.white,
                radius: 14,
              ),
        const SizedBox(height: 2), // daha az boşluk
        const Text(
          "Çocuk İsmi:",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        Text(
          child["appcustomer_name"] != null && child["appcustomer_name"].toString().trim().isNotEmpty
              ? child["appcustomer_name"]
              : "İsim yok",
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        // Divider yerine ince bir çizgi veya hiç kullanmayabilirsin
        // Container(height: 1, color: Colors.grey[300]),
        FutureBuilder<String>(
          future: getShortAddress(child["latitude"], child["longitude"]),
          builder: (context, snapshot) {
            String addr = snapshot.data ?? "Adres getirilemedi";
            return Row(
              children: [
                const Icon(Icons.place, size: 11, color: Colors.green),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    "Adres: $addr",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            );
          },
        ),
        Row(
          children: [
            const Icon(Icons.access_time, size: 11, color: primaryColor),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                "Tarih: ${formatTimestamp(child["timestamp"])}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        // HARİTA ALANI (ALTTA, TÜM GENİŞLİKTE)
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter:
                      myPosition ?? LatLng(39.925533, 32.866287),
                  initialZoom: myPosition != null ? 8 : 5,
                  onLongPress: (_tapPos, latlng) async {
                    if (_userType == 'Aile') {
                      await _showRadiusSelectionDialog(context, latlng);
                    }
                  },
                ),
                mapController: mapController,
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$mapTilerKey',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.example.app',
                  ),
                  MarkerLayer(markers: markers),
                  if (_areaCenter != null && _areaRadiusMeter != null)
                    PolygonLayer(
                      polygons: [
                        Polygon(
                          points: _createCirclePoints(
                              _areaCenter!, _areaRadiusMeter!),
                          color: accentColor.withOpacity(0.17),
                          borderColor: areaBorderColor,
                          borderStrokeWidth: 3,
                        ),
                      ],
                    ),
                ],
              ),
              // "Alan Seç" butonu (harita üstünde sağ üstte sabit)
              if (_userType == 'Aile')
                Positioned(
                  top: 18,
                  right: 18,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.gps_fixed, color: primaryColor),
                    label: const Text('Alan Seç',
                        style: TextStyle(color: primaryColor)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: primaryColor, width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Haritada uzun basarak merkez seçin!'),
                          backgroundColor: accentColor.withOpacity(0.95),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

  List<LatLng> _createCirclePoints(LatLng center, double radiusMeter, {int points = 72}) {
    const earthRadius = 6371000.0;
    final List<LatLng> circlePoints = [];
    final double lat = center.latitude * pi / 180.0;
    for (int i = 0; i <= points; i++) {
      final double angle = 2 * pi * i / points;
      final double dx = radiusMeter * cos(angle);
      final double dy = radiusMeter * sin(angle);
      final double latOffset = dx / earthRadius;
      final double lngOffset = dy / (earthRadius * cos(lat));
      final double pointLat = lat + latOffset;
      final double pointLng = center.longitude * pi / 180.0 + lngOffset;
      circlePoints.add(LatLng(pointLat * 180.0 / pi, pointLng * 180.0 / pi));
    }
    return circlePoints;
  }
}
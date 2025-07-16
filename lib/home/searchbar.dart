import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  MapController mapController = MapController();

  List<Marker> markers = [];
  List<Map<String, dynamic>> allLocations = [];
  LatLng? myPosition;
  String searchQuery = '';

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

  static const String locationIqApiKey = 'pk.fa04e03ad4bc91e7e95e2d5e33fd249b'; // <-- BURAYA kendi API key'ini yaz!
  static const String mapTilerKey = '9mDxXPWnyEAbexVqNUJs'; // <-- BURAYA KENDİ MAPTILER API KEY'İNİ YAZ!

  @override
  void initState() {
    super.initState();
    developer.log('initState ÇALIŞTI', name: 'DEBUG');
    print("SearchPage initState ÇALIŞTI");
    _loadUserInfo().then((_) async {
      print('initState: _userType=$_userType, _userId=$_userId, _parentId=$_parentId');
      if (_userType == 'Aile' && _userId != null) {
        await _loadChildrenCurrentLocations(_userId!);
        print('buraya girdi: _userType=$_userType, _userId=$_userId');
      } else {
        print('else bloğu, şart sağlanmadı! _userType=$_userType, _userId=$_userId');
      }
      _listenLocations();
      _listenAreaLimit();
      _getCurrentLocation();
      if (_userType == 'Aile') {
        _startPositionStream();
      }
    }).catchError((e, st) {
      developer.log('initState: then bloğunda hata: $e $st', name: 'DEBUG');
    });
  }

  Future<void> _loadUserInfo() async {
    try {
      developer.log('_loadUserInfo: başladı', name: 'DEBUG');
      final prefs = await SharedPreferences.getInstance();
      developer.log('_loadUserInfo: prefs alındı', name: 'DEBUG');
      if (_disposed) return;
      setState(() {
        _userId = prefs.getInt('user_id');
        _parentId = prefs.getInt('parent_id');
        _userType = prefs.getString('user_type');
        _userName = prefs.getString('appcustomer_name');
      });
      developer.log('_loadUserInfo: bitti $_userId, $_userType', name: 'DEBUG');
    } catch (e, st) {
      developer.log('_loadUserInfo: hata $e $st', name: 'DEBUG');
    }
  }

  void _listenAreaLimit() {
    final areaLimitId = _userType == 'Aile' ? _userId?.toString() : _parentId?.toString();
    developer.log('_listenAreaLimit: areaLimitId=$areaLimitId', name: 'DEBUG');
    if (areaLimitId == null) return;
    _areaLimitSubscription?.cancel();
    _areaLimitSubscription = firestore
        .collection('area_limits')
        .doc(areaLimitId)
        .snapshots()
        .listen((doc) {
      if (_disposed) return;
      developer.log('_listenAreaLimit: doc.exists=${doc.exists} doc.data=${doc.data()}', name: 'DEBUG');
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
    developer.log('_listenLocations: _userId=$_userId, _userType=$_userType', name: 'DEBUG');
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
              'name': data['appcustomer_name'] ?? data['name'] ?? '',
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
              'name': data['appcustomer_name'] ?? data['name'] ?? '',
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

  /// LocationIQ ile kısa adres döner
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
    print("LocationIQ response (${response.statusCode}): ${response.body}");
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final address = data['display_name']?.toString() ?? '';
      if (address.isNotEmpty && address != "Adres getirilemedi") {
        _addressCache[key] = address;
        return address;
      }
    }
  } catch (e) {
    print("Adres hatası: $e");
  }
  // Yeniden denesin (max 2 tekrar)
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
        'name': data['appcustomer_name'] ?? data['name'] ?? '',
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
        'name': _userName ?? '',
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

  void _updateMarkers() {
    List<Marker> newMarkers = [];

    for (var i = 0; i < allLocations.length; i++) {
      var loc = allLocations[i];
      final profileImageUrl = loc['profile_image_url'];
      newMarkers.add(
        Marker(
          point: loc['position'],
          width: 46,
          height: 46,
          child: Tooltip(
            message: loc['name'],
            child: (profileImageUrl != null && profileImageUrl.toString().isNotEmpty)
                ? ClipOval(
                    child: Image.network(
                      profileImageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.person_pin_circle,
                        color: loc['user_type'] == 'Çocuk' ? Colors.green : Colors.blue,
                        size: 35,
                      ),
                    ),
                  )
                : Icon(
                    Icons.person_pin_circle,
                    color: loc['user_type'] == 'Çocuk' ? Colors.green : Colors.blue,
                    size: 35,
                  ),
          ),
        ),
      );
    }

    if (myPosition != null) {
      newMarkers.add(
        Marker(
          point: myPosition!,
          width: 48,
          height: 48,
          child: Tooltip(
            message: "Benim Konumum",
            child: Icon(
              Icons.location_on,
              color: Colors.red,
              size: 44,
            ),
          ),
        ),
      );
    }

    markers = newMarkers;
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
          const SnackBar(
            content: Text('Dikkat! Alan sınırının dışındasın!'),
            backgroundColor: Colors.red,
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
          title: Text('Alan Seç (km²)'),
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
                      onChanged: (v) {
                        setStateDialog(() {
                          tempArea = v;
                        });
                      },
                    ),
                    Text('${tempArea.toStringAsFixed(1)} km²'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
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
              child: Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _firestoreLocationSubscription?.cancel();
    _positionStreamSubscription?.cancel();
    _areaLimitSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    developer.log(
        'build: _userType=$_userType, _childCurrentLocations.isNotEmpty=${_childCurrentLocations.isNotEmpty}',
        name: 'DEBUG');
    return Scaffold(
      backgroundColor: const Color(0xFFff1585).withOpacity(0.03),
      appBar: AppBar(
        title: const Text('Konum Bul'),
        backgroundColor: const Color(0xFF5e17eb),
        foregroundColor: Colors.white,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFff1585), width: 4),
                borderRadius: BorderRadius.circular(22),
              ),
              margin: const EdgeInsets.all(10),
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: myPosition ?? LatLng(39.925533, 32.866287),
                      initialZoom: myPosition != null ? 8 : 5, // <<< BURAYI DEĞİŞTİRDİK!
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
                              color:
                                  const Color(0xFFff1585).withOpacity(0.13),
                              borderColor: const Color(0xFF5e17eb),
                              borderStrokeWidth: 3,
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_userType == 'Aile')
                    Positioned(
                      top: 18,
                      right: 18,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.gps_fixed,
                            color: Color(0xFF5e17eb)),
                        label: const Text('Alan Seç',
                            style: TextStyle(color: Color(0xFF5e17eb))),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(
                              color: Color(0xFF5e17eb), width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Haritada uzun basarak merkez seçin!')),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_userType == 'Aile' && _childCurrentLocations.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Çocukların Güncel Konumları',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _childCurrentLocations
                          .map(
                            (child) => Card(
                              color: Colors.blue.shade50,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Container(
                                width: 275,
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        (child["profile_image_url"] != null &&
                                                child["profile_image_url"]
                                                    .toString()
                                                    .isNotEmpty)
                                            ? CircleAvatar(
                                                backgroundImage: NetworkImage(
                                                    child["profile_image_url"]),
                                              )
                                            : const CircleAvatar(
                                                child: Icon(Icons.person)),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            child["name"] != null &&
                                                    child["name"]
                                                        .toString()
                                                        .trim()
                                                        .isNotEmpty
                                                ? "Çocuğun İsmi : ${child["name"]}"
                                                : "Çocuğun İsmi : yok",
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(),
                                    FutureBuilder<String>(
                                      future: getShortAddress(
                                          child["latitude"],
                                          child["longitude"]),
                                      builder: (context, snapshot) {
                                        String addr =
                                            snapshot.data ?? "Adres getirilemedi";
                                        return Row(
                                          children: [
                                            const Icon(Icons.place,
                                                size: 16, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                "Adres: $addr",
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time,
                                            size: 16, color: Colors.purple),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            "Tarih: ${formatTimestamp(child["timestamp"])}",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<LatLng> _createCirclePoints(LatLng center, double radiusMeter,
      {int points = 72}) {
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
      circlePoints.add(LatLng(
          pointLat * 180.0 / pi,
          pointLng * 180.0 / pi));
    }
    return circlePoints;
  }
}
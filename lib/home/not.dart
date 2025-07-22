import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Renkler
const Color kPrimaryPink = Color(0xFFFF1585);
const Color kPrimaryPurple = Color(0xFF5E17EB);

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.userFilter = ""});
  final String userFilter;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> with WidgetsBindingObserver {
  String _searchFilter = "";
  int? _userId;
  String? _userType;
  Set<String> _restrictedPackages = {};
  Timer? _watchdogTimer;
  static const platform = MethodChannel('com.example.app/usage_stats');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFilter = "";
    _loadUserInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdogTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
      _userType = prefs.getString('user_type');
    });
    debugPrint('[_loadUserInfo] userId: $_userId, userType: $_userType');
  }


Future<String?> getGooglePlayIconUrl(String packageName) async {
  try {
    final url = 'https://play.google.com/store/apps/details?id=$packageName';
    final response = await http.get(Uri.parse(url), headers: {
      // User-Agent eklemek önemli, bazen olmadan response farklı döner!
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'
    });
    debugPrint('[getGooglePlayIconUrl] Status code: ${response.statusCode}');
    if (response.statusCode == 200) {
      debugPrint('[getGooglePlayIconUrl] Response body (ilk 500): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
      // YENİ REGEXP!
      final regExp = RegExp(
        r'<meta property="og:image" content="([^"]+)"',
        caseSensitive: false,
      );
      final match = regExp.firstMatch(response.body);
      debugPrint('[getGooglePlayIconUrl] RegExp match: $match');
      if (match != null && match.groupCount >= 1) {
        String iconUrl = match.group(1)!;
        debugPrint('[getGooglePlayIconUrl] Found iconUrl: $iconUrl');
        return iconUrl;
      } else {
        debugPrint('[getGooglePlayIconUrl] Icon not found in HTML!');
      }
    } else {
      debugPrint('[getGooglePlayIconUrl] HTTP status code not 200!');
    }
  } catch (e) {
    debugPrint('[getGooglePlayIconUrl] Exception: $e');
  }
  return null;
}

  // --- YENİ: App icon provider (önce cihazda, yoksa Google Play) ---
 Future<ImageProvider?> getAppIconProvider(String packageName) async {
  try {
    // Önce cihazdan çekmeyi dene
    final Uint8List? iconBytes = await platform.invokeMethod<Uint8List>(
      'getAppIcon',
      {"packageName": packageName},
    );
    if (iconBytes != null) {
      return MemoryImage(iconBytes);
    }
  } catch (e) {
    debugPrint('[getAppIconProvider] Cihazdan ikon alınamadı: $e');
    // ignore, aşağıda Google Play'den dene
  }
  // Cihazda yoksa Google Play'den çekmeyi dene
  final iconUrl = await getGooglePlayIconUrl(packageName);
  if (iconUrl != null) {
    return NetworkImage(iconUrl);
  }
  return null;
}

  Future<void> _startWatchdog(Set<String> restrictedPackages) async {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final List? appList = await platform.invokeMethod<List>('getUsageStats');
        debugPrint('[_startWatchdog] appList: $appList');
        if (appList != null) {
          for (final item in appList) {
            if (item is Map) {
              final String? packageName = item['packageName']?.toString();
              final int hours = int.tryParse(item['hours'].toString()) ?? 0;
              final int minutes = int.tryParse(item['minutes'].toString()) ?? 0;
              final bool isInForeground = (hours > 0 || minutes > 0);
              debugPrint('[_startWatchdog] packageName: $packageName, isInForeground: $isInForeground, restricted: ${restrictedPackages.contains(packageName)}');
              if (restrictedPackages.contains(packageName) && isInForeground) {
                _watchdogTimer?.cancel();
                if (mounted) {
                  SystemNavigator.pop();
                }
                break;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[_startWatchdog] Error: $e');
      }
    });
  }

  Map<String, List<Map<String, dynamic>>> _processSnapshot(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final Map<String, Map<String, dynamic>> filterStats = {};
    final Set<String> allRestrictedPackages = {};

    for (var doc in snapshot.docs) {
      if (_userId == null) continue;
      final idParts = doc.id.split('_');
      final filter = idParts.sublist(1).join('_');
      final data = doc.data();
      final statsRaw = data['stats'];
      Map<String, dynamic> stats = {};
      if (statsRaw is Map) {
        stats = Map<String, dynamic>.from(statsRaw);
      } else if (statsRaw is List) {
        for (var appEntry in statsRaw) {
          if (appEntry is Map && appEntry['appName'] != null) {
            stats[appEntry['appName']] = appEntry;
          }
        }
      }
      final appCustomerName = data['appcustomer_name'] ?? "";
      List<dynamic> restrictedApps = [];
      if (data.containsKey('restricted_apps')) {
        restrictedApps = List<dynamic>.from(data['restricted_apps']);
        for (var item in restrictedApps) {
          if (item is Map && item.containsKey('packageName')) {
            allRestrictedPackages.add(item['packageName']);
          } else if (item is Map && item.containsKey('appName')) {
            allRestrictedPackages.add(item['appName']);
          } else if (item is String) {
            allRestrictedPackages.add(item);
          }
        }
      }
      stats.forEach((appNameKey, statMap) {
        final stat = Map<String, dynamic>.from(statMap ?? {});
        final int hours = stat['hours'] ?? 0;
        final int minutes = stat['minutes'] ?? 0;
        final int totalMinutes = (hours * 60) + minutes;
        final String packageName = stat['packageName'] ?? appNameKey;
        final String appName = stat['appName'] ?? appNameKey;

        bool isRestricted = false;
        if (restrictedApps.isNotEmpty) {
          isRestricted = restrictedApps.any((item) {
            if (item is Map && item['packageName'] == packageName) return true;
            if (item is Map && item['appName'] == packageName) return true;
            if (item is String && item == packageName) return true;
            return false;
          });
        }
        if (!filterStats.containsKey(filter)) {
          filterStats[filter] = {};
        }
        if (!filterStats[filter]!.containsKey(packageName)) {
          filterStats[filter]![packageName] = {
            'appName': appName,
            'packageName': packageName,
            'hours': hours,
            'minutes': minutes,
            'totalMinutes': totalMinutes,
            'docId': doc.id,
            'restricted': isRestricted,
            'appcustomer_name': appCustomerName,
          };
        } else {
          filterStats[filter]![packageName]['hours'] += hours;
          filterStats[filter]![packageName]['minutes'] += minutes;
          filterStats[filter]![packageName]['totalMinutes'] += totalMinutes;
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_watchdogTimer == null || !_watchdogTimer!.isActive || _restrictedPackages != allRestrictedPackages) {
        _watchdogTimer?.cancel();
        _restrictedPackages = allRestrictedPackages;
        _startWatchdog(_restrictedPackages);
      }
    });

    final Map<String, List<Map<String, dynamic>>> topStats = {};
    filterStats.forEach((filter, appStatMap) {
      final statList = appStatMap.values.toList();
      statList.sort((a, b) => (b['totalMinutes'] as int).compareTo(a['totalMinutes'] as int));
      topStats[filter] = statList.take(10).toList().cast<Map<String, dynamic>>();
    });
    debugPrint('[_processSnapshot] topStats: $topStats');
    return topStats;
  }

  Future<void> _addRestriction(String docId, String packageName, DateTime untilDate, String appName) async {
    final docRef = FirebaseFirestore.instance.collection('user_usagestats').doc(docId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    List<dynamic> restrictedApps = [];
    if (data.containsKey('restricted_apps')) {
      restrictedApps = List<dynamic>.from(data['restricted_apps']);
    }
    restrictedApps.removeWhere((item) =>
        (item is Map && item['packageName'] == packageName) ||
        (item is Map && item['appName'] == packageName) ||
        (item is String && item == packageName)
    );

    restrictedApps.add({'packageName': packageName, 'until': untilDate.toIso8601String()});

    await docRef.update({
      'restricted_apps': restrictedApps,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kPrimaryPink,
          content: Text('$appName uygulamasına $untilDate tarihine kadar kısıtlama getirildi.'),
        ),
      );
    }
  }

  Future<void> _removeRestriction(String docId, String packageName, String appName) async {
    final docRef = FirebaseFirestore.instance.collection('user_usagestats').doc(docId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    List<dynamic> restrictedApps = [];
    if (data.containsKey('restricted_apps')) {
      restrictedApps = List<dynamic>.from(data['restricted_apps']);
    }
    restrictedApps.removeWhere((item) =>
        (item is Map && item['packageName'] == packageName) ||
        (item is Map && item['appName'] == packageName) ||
        (item is String && item == packageName)
    );

    await docRef.update({
      'restricted_apps': restrictedApps,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kPrimaryPurple,
          content: Text('$appName uygulamasının kısıtlaması kaldırıldı.'),
        ),
      );
    }
  }

  void _onRestrictionTap(String docId, String packageName, String appName, bool isRestricted) async {
    debugPrint('[_onRestrictionTap] docId: $docId, packageName: $packageName, appName: $appName, isRestricted: $isRestricted');
    if (isRestricted) {
      await _removeRestriction(docId, packageName, appName);
    } else {
      DateTime? selectedDateTime = await showDialog<DateTime>(
        context: context,
        builder: (context) => DateTimeRestrictionDialog(appName: appName),
      );
      if (selectedDateTime != null) {
        await _addRestriction(docId, packageName, selectedDateTime, appName);
      }
    }
  }

  void _onAppTap(String docId, String packageName, String appName, bool isRestricted) async {
    debugPrint('[_onAppTap] docId: $docId, packageName: $packageName, appName: $appName, isRestricted: $isRestricted');
    if (isRestricted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.block, color: kPrimaryPink),
                const SizedBox(width: 8),
                const Text("Kısıtlama"),
              ],
            ),
            content: Text("$appName uygulamasına bu filtrede giriş yasak!"),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: kPrimaryPink,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("Tamam"),
              ),
            ],
          ),
        );
      }
      return;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.black,
          content: Text('$appName uygulaması açılabilir (kısıt yok).'),
        ),
      );
    }
  }

  Widget _buildAppTile(Map<String, dynamic> stat) {
    final appCustomerName = stat['appcustomer_name'] ?? '';
    final appName = stat['appName'] ?? 'Bilinmeyen Uygulama';
    final packageName = stat['packageName'] ?? appName;
    final hours = stat['hours'] ?? 0;
    final minutes = stat['minutes'] ?? 0;
    final docId = stat['docId'];
    final bool isRestricted = stat['restricted'] == true;

    debugPrint('[_buildAppTile] appName: $appName, packageName: $packageName, docId: $docId');
  if (packageName == "com.miui.home" || appName.toLowerCase() == "home") {
    return const SizedBox.shrink();
  }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            _onAppTap(docId, packageName, appName, isRestricted);
          },
          child: Container(
            constraints: const BoxConstraints(
              maxHeight: 55,
              maxWidth: 270,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF8D6E63).withOpacity(0.15),
              border: Border.all(
                color: const Color(0xFF8D6E63),
                width: 2,
              ), 
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
            child: Row(
              children: [
                // --- Sadece ikon veya harf göster (YUVARLAK YOK!) ---
                FutureBuilder<ImageProvider?>(
                  future: getAppIconProvider(packageName),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      return Image(
                        image: snapshot.data!,
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                      );
                    } else {
                      return Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        child: Text(
                          appCustomerName.isNotEmpty
                              ? appCustomerName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appName,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        (hours > 0)
                            ? 'Süre: $hours saat $minutes dakika'
                            : 'Süre: $minutes dakika',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.normal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: isRestricted
                      ? const Icon(Icons.block, color: Colors.red)
                      : const Icon(Icons.check_circle, color: Colors.brown),
                  tooltip: isRestricted
                      ? "Kısıtlamayı kaldır"
                      : "Bu uygulamaya kısıtlama ekle",
                  onPressed: () {
                    _onRestrictionTap(docId, packageName, appName, isRestricted);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(String filter, List<Map<String, dynamic>> topStats) {
    final String customerName = (topStats.isNotEmpty && topStats.first['appcustomer_name'] != null)
        ? topStats.first['appcustomer_name']
        : '';
    return Card(
      elevation: 5,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '$customerName$filter',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: 0.7,
                ),
              ),
              const Divider(color: Colors.white38, thickness: 1.3),
              ...topStats.map(_buildAppTile),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F2FC),
      appBar: AppBar(
        iconTheme: IconThemeData(color: Colors.white),
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Ziyaret Edilen Uygulamalar',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 19),
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
      ),
      body: (_userId == null || _userType == null)
          ? const Center(child: CircularProgressIndicator())
          : _userType == "Aile"
              ? Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.brown, width: 2),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: kPrimaryPink.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: TextField(
                        style: const TextStyle(color: kPrimaryPurple, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Filtre adına göre ara...',
                          labelStyle: TextStyle(color: Colors.brown.withOpacity(0.8)),
                          prefixIcon: Icon(Icons.search, color: Colors.brown),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchFilter = value.trim();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('user_usagestats')
                            .where('parent_id', isEqualTo: _userId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          debugPrint('[StreamBuilder] hasError: ${snapshot.hasError}, hasData: ${snapshot.hasData}, doc length: ${snapshot.data?.docs.length}, _userId: $_userId');
                          if (snapshot.hasError) {
                            return const Center(child: Text("Bir hata oluştu!", style: TextStyle(color: Colors.black)));
                          }
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final _filterTopStats = _processSnapshot(snapshot.data!);
                          final _allFilters = _filterTopStats.keys.toList();
                          final filtersToShow = _searchFilter.isEmpty
                              ? _allFilters
                              : _allFilters
                                  .where((f) => f.toLowerCase().contains(_searchFilter.toLowerCase()))
                                  .toList();

                          if (filtersToShow.isEmpty) {
                            return const Center(child: Text("Kayıt bulunamadı.", style: TextStyle(color: Colors.black)));
                          }

                          return ListView.builder(
                            itemCount: filtersToShow.length,
                            itemBuilder: (context, filterIndex) {
                              final filter = filtersToShow[filterIndex];
                              final topStats = _filterTopStats[filter] ?? [];
                              return _buildFilterCard(filter, topStats);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: Text(
                    "Sadece Aile kullanıcıları uygulama istatistiklerini görebilir.",
                    style: TextStyle(fontSize: 17, color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
    );
  }
}

class DateTimeRestrictionDialog extends StatefulWidget {
  final String appName;
  const DateTimeRestrictionDialog({Key? key, required this.appName}) : super(key: key);

  @override
  State<DateTimeRestrictionDialog> createState() => _DateTimeRestrictionDialogState();
}

class _DateTimeRestrictionDialogState extends State<DateTimeRestrictionDialog> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("${widget.appName} için tarih ve saat limiti"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            child: Text(_selectedDate == null
                ? "Tarih seç"
                : "${_selectedDate!.day}.${_selectedDate!.month}.${_selectedDate!.year}"),
          ),
          ElevatedButton(
            onPressed: () async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null) setState(() => _selectedTime = time);
            },
            child: Text(_selectedTime == null
                ? "Saat seç"
                : "${_selectedTime!.hour.toString().padLeft(2, "0")}:${_selectedTime!.minute.toString().padLeft(2, "0")}"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Vazgeç"),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedDate != null && _selectedTime != null) {
              final target = DateTime(
                _selectedDate!.year,
                _selectedDate!.month,
                _selectedDate!.day,
                _selectedTime!.hour,
                _selectedTime!.minute,
              );
              Navigator.pop(context, target);
            }
          },
          child: const Text("Kaydet"),
        ),
      ],
    );
  }
}
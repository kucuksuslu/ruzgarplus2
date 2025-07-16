import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  }

  Future<void> _startWatchdog(Set<String> restrictedApps) async {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final List? appList = await platform.invokeMethod<List>('getUsageStats');
        if (appList != null) {
          for (final item in appList) {
            if (item is Map) {
              final String? packageName = item['packageName']?.toString();
              final int hours = int.tryParse(item['hours'].toString()) ?? 0;
              final int minutes = int.tryParse(item['minutes'].toString()) ?? 0;
              final bool isInForeground = (hours > 0 || minutes > 0);
              if (restrictedApps.contains(packageName) && isInForeground) {
                _watchdogTimer?.cancel();
                if (mounted) {
                  SystemNavigator.pop();
                }
                break;
              }
            }
          }
        }
      } catch (e) {}
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
      final stats = Map<String, dynamic>.from(data['stats'] ?? {});
      final appCustomerName = data['appcustomer_name'] ?? "";
      List<dynamic> restrictedApps = [];
      if (data.containsKey('restricted_apps')) {
        restrictedApps = List<dynamic>.from(data['restricted_apps']);
        // Eğer yeni yapıda ise (Map olarak), isimleri ayıkla:
        for (var item in restrictedApps) {
          if (item is Map && item.containsKey('appName')) {
            allRestrictedPackages.add(item['appName']);
          } else if (item is String) {
            allRestrictedPackages.add(item);
          }
        }
      }
      stats.forEach((appName, statMap) {
        final stat = Map<String, dynamic>.from(statMap ?? {});
        final int hours = stat['hours'] ?? 0;
        final int minutes = stat['minutes'] ?? 0;
        final int totalMinutes = (hours * 60) + minutes;
        if (!filterStats.containsKey(filter)) {
          filterStats[filter] = {};
        }
        // Kısıtlı mı?
        bool isRestricted = false;
        // restrictedApps elemanları hem Map hem String olabilir
        if (restrictedApps.isNotEmpty) {
          isRestricted = restrictedApps.any((item) {
            if (item is Map && item['appName'] == appName) return true;
            if (item is String && item == appName) return true;
            return false;
          });
        }
        // Map'in içine yaz
        if (!filterStats[filter]!.containsKey(appName)) {
          filterStats[filter]![appName] = {
            'appName': appName,
            'hours': hours,
            'minutes': minutes,
            'totalMinutes': totalMinutes,
            'docId': doc.id,
            'restricted': isRestricted,
            'appcustomer_name': appCustomerName,
          };
        } else {
          filterStats[filter]![appName]['hours'] += hours;
          filterStats[filter]![appName]['minutes'] += minutes;
          filterStats[filter]![appName]['totalMinutes'] += totalMinutes;
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
    return topStats;
  }

  Future<void> _addRestriction(String docId, String appName, DateTime untilDate) async {
    final docRef = FirebaseFirestore.instance.collection('user_usagestats').doc(docId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    List<dynamic> restrictedApps = [];
    if (data.containsKey('restricted_apps')) {
      restrictedApps = List<dynamic>.from(data['restricted_apps']);
    }
    // Aynı uygulama varsa önce sil
    restrictedApps.removeWhere((item) =>
      (item is Map && item['appName'] == appName) ||
      (item is String && item == appName)
    );

    restrictedApps.add({'appName': appName, 'until': untilDate.toIso8601String()});

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

  Future<void> _removeRestriction(String docId, String appName) async {
    final docRef = FirebaseFirestore.instance.collection('user_usagestats').doc(docId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    List<dynamic> restrictedApps = [];
    if (data.containsKey('restricted_apps')) {
      restrictedApps = List<dynamic>.from(data['restricted_apps']);
    }
    restrictedApps.removeWhere((item) =>
      (item is Map && item['appName'] == appName) ||
      (item is String && item == appName)
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

  void _onRestrictionTap(String docId, String appName, bool isRestricted) async {
    if (isRestricted) {
      await _removeRestriction(docId, appName);
    } else {
      // Tarih ve saat seçtir
      DateTime? selectedDateTime = await showDialog<DateTime>(
        context: context,
        builder: (context) => DateTimeRestrictionDialog(appName: appName),
      );
      if (selectedDateTime != null) {
        await _addRestriction(docId, appName, selectedDateTime);
      }
    }
  }

  void _onAppTap(String docId, String appName, bool isRestricted) async {
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
          backgroundColor: kPrimaryPurple,
          content: Text('$appName uygulaması açılabilir (kısıt yok).'),
        ),
      );
    }
  }

  Widget _buildAppTile(Map<String, dynamic> stat) {
    final appCustomerName = stat['appcustomer_name'] ?? '';
    final appName = stat['appName'] ?? 'Bilinmeyen Uygulama';
    final hours = stat['hours'] ?? 0;
    final minutes = stat['minutes'] ?? 0;
    final docId = stat['docId'];
    final bool isRestricted = stat['restricted'] == true;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isRestricted ? kPrimaryPink.withOpacity(0.15) : kPrimaryPurple.withOpacity(0.11),
        child: appCustomerName.isNotEmpty
            ? Text(
                appCustomerName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              )
            : Icon(Icons.apps, color: Colors.white),
      ),
      title: Text(
        appName,
        style: TextStyle(
          color: Colors.white,
          fontWeight: isRestricted ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        (hours > 0)
            ? 'Süre: $hours saat $minutes dakika'
            : 'Süre: $minutes dakika',
        style: TextStyle(
          color: Colors.white,
          fontWeight: isRestricted ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: IconButton(
        icon: isRestricted
            ? const Icon(Icons.block, color: Colors.white)
            : const Icon(Icons.check_circle, color: Colors.white),
        tooltip: isRestricted
            ? "Kısıtlamayı kaldır"
            : "Bu uygulamaya kısıtlama ekle",
        onPressed: () {
          _onRestrictionTap(docId, appName, isRestricted);
        },
      ),
      onTap: () {
        _onAppTap(docId, appName, isRestricted);
      },
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
          gradient: LinearGradient(
            colors: [kPrimaryPurple.withOpacity(0.93), kPrimaryPink.withOpacity(0.92)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${customerName}${filter}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
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
        backgroundColor: kPrimaryPink,
        elevation: 0,
        title: const Text(
          'Filtrelere Göre En Çok Kullanılan 7 Uygulama',
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
                          labelStyle: TextStyle(color: kPrimaryPurple.withOpacity(0.8)),
                          prefixIcon: Icon(Icons.search, color: kPrimaryPink),
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
                          print('[DEBUG] StreamBuilder snapshot.hasData: ${snapshot.hasData}'
                              ', doc length: ${snapshot.data?.docs.length ?? 'null'}'
                              ', _userId: $_userId');
                          if (snapshot.hasError) {
                            return const Center(child: Text("Bir hata oluştu!", style: TextStyle(color: Colors.white)));
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
                            return const Center(child: Text("Kayıt bulunamadı.", style: TextStyle(color: Colors.white)));
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
                    style: TextStyle(fontSize: 17, color: kPrimaryPurple, fontWeight: FontWeight.bold),
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
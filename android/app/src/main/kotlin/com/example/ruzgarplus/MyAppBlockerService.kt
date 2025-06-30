package com.example.ruzgarplus

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

class MyAppBlockerService : AccessibilityService() {

    private val TAG = "AppBlockerService"
    private val systemPackages = setOf(
        "com.android.systemui",
        "com.miui.securitycenter",
        "com.android.settings",
        "com.mi.android.globallauncher",
        "com.sec.android.app.launcher",
        "com.google.android.apps.nexuslauncher",
        "com.huawei.android.launcher"
    )

    private var blockedAppsFromFirebase: Set<String> = emptySet()
    private var overlayVisible = false
    private var lastBlockedPkg: String? = null
    private var nonBlockedEventCount = 0

    private var userId: String? = null
    private var selectedFilter: String = "None"

    // Firestore listener registration nesnesi
    private var firestoreListenerRegistration: ListenerRegistration? = null

    override fun onServiceConnected() {
        Log.i(TAG, "onServiceConnected: Erişilebilirlik servisi BAŞLADI.")

        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info

        // SharedPreferences'tan user_id ve filter bilgisini al
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val anyUserId = prefs.all["flutter.user_id"]
        userId = when (anyUserId) {
            is String -> anyUserId
            is Long -> anyUserId.toString()
            is Int -> anyUserId.toString()
            else -> null
        }
        selectedFilter = prefs.getString("flutter.selected_filter", "None") ?: "None"
        Log.d(TAG, "Kullanıcı: $userId, Filtre: $selectedFilter")

        // Firestore'dan bloklu uygulama listesini dinle (gerçek zamanlı)
        listenBlockedAppsFromFirebase()
    }

    /**
     * Uygulama ismine göre cihazda yüklü uygulamalar arasından packageName bulur.
     * Eğer uygulama bulunamazsa null döner.
     */
    private fun resolvePackageNameFromAppName(appName: String): String? {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        val allApps = pm.queryIntentActivities(intent, 0)
        for (app in allApps) {
            val label = app.loadLabel(pm).toString().trim().lowercase()
            if (label == appName.trim().lowercase()) {
                Log.d(TAG, "resolvePackageNameFromAppName: $appName için bulunan package: ${app.activityInfo.packageName}")
                return app.activityInfo.packageName
            }
        }
        Log.w(TAG, "resolvePackageNameFromAppName: $appName için package bulunamadı!")
        return null
    }

    private fun listenBlockedAppsFromFirebase() {
        val uid = userId
        if (uid == null || selectedFilter == "None") {
            Log.w(TAG, "Kullanıcı veya filtre yok, Firestore dinleyici atlanıyor.")
            blockedAppsFromFirebase = emptySet()
            firestoreListenerRegistration?.remove()
            firestoreListenerRegistration = null
            return
        }
        val docId = "${uid}_${selectedFilter}"
        val firestore = FirebaseFirestore.getInstance()
        Log.d(TAG, "Firestore dinleyici başlatılıyor: $docId")
        firestoreListenerRegistration?.remove() // Öncekini temizle
        firestoreListenerRegistration = firestore.collection("user_usagestats")
            .document(docId)
            .addSnapshotListener { doc, error ->
                if (error != null) {
                    blockedAppsFromFirebase = emptySet()
                    Log.e(TAG, "Firestore dinleyici hatası: ${error.message}")
                    return@addSnapshotListener
                }
                if (doc != null && doc.exists()) {
                    Log.d(TAG, "Firestore listener -> doküman: ${doc.data}")
                    val restrictedApps = doc.get("restricted_apps") as? List<*>
                    if (restrictedApps != null) {
                        blockedAppsFromFirebase = restrictedApps.mapNotNull { appName ->
                            val appNameStr = appName?.toString()?.trim() ?: return@mapNotNull null
                            // Zaten bir package name ise aynen al
                            if (appNameStr.startsWith("com.")) {
                                Log.d(TAG, "Firestore app: $appNameStr doğrudan package olarak eklendi.")
                                appNameStr
                            } else {
                                // Otomatik olarak package name bulmaya çalış
                                val foundPackage = resolvePackageNameFromAppName(appNameStr)
                                if (foundPackage != null) {
                                    Log.d(TAG, "Firestore app: $appNameStr otomatik olarak $foundPackage package ismine eşlendi.")
                                }
                                foundPackage
                            }
                        }.toSet()
                        Log.d(TAG, "Firebase'den bloklu uygulamalar (listener): $blockedAppsFromFirebase")
                    } else {
                        blockedAppsFromFirebase = emptySet()
                        Log.d(TAG, "restricted_apps alanı yok, bloklu uygulama listesi boş.")
                    }
                } else {
                    blockedAppsFromFirebase = emptySet()
                    Log.w(TAG, "Firestore: Doküman bulunamadı ($docId), bloklu uygulama listesi boş.")
                }
            }
    }

override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    if (event == null) return

    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
    val newSelectedFilter = prefs.getString("flutter.selected_filter", "None") ?: "None"
    if (newSelectedFilter != selectedFilter) {
        selectedFilter = newSelectedFilter
        listenBlockedAppsFromFirebase()
    }

    // SADECE "Aile" DEĞİLSE overlay ve engelleme kontrolleri yapılır!
    if (selectedFilter != "Aile") {
        val eventType = event.eventType
        val pkg = event.packageName?.toString() ?: return

        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            Log.d(TAG, "blockedAppsFromFirebase kontrol: $blockedAppsFromFirebase, O anda açılan: $pkg")
            when {
                blockedAppsFromFirebase.contains(pkg) -> {
                    if (!overlayVisible) {
                        try {
                            if (Settings.canDrawOverlays(this)) {
                                startService(Intent(this, OverlayBlockerService::class.java))
                                overlayVisible = true
                                Log.d(TAG, "Overlay servisi başlatıldı.")
                            } else {
                                Handler(Looper.getMainLooper()).post {
                                    Toast.makeText(this, "Lütfen uygulama için 'Diğer uygulamaların üstünde göster' iznini verin.", Toast.LENGTH_LONG).show()
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Overlay başlatılamadı: ${e.message}", e)
                        }
                    }
                    lastBlockedPkg = pkg
                    nonBlockedEventCount = 0
                }
                systemPackages.contains(pkg) -> {
                    Log.d(TAG, "Sistem uygulamasına geçildi ($pkg), overlay aynen açık kalacak.")
                }
                else -> {
                    if (overlayVisible && lastBlockedPkg != null) {
                        nonBlockedEventCount++
                        Log.d(TAG, "Blocked pkg yok ($pkg), sayaç: $nonBlockedEventCount")
                        if (nonBlockedEventCount >= 2) {
                            stopService(Intent(this, OverlayBlockerService::class.java))
                            overlayVisible = false
                            lastBlockedPkg = null
                            nonBlockedEventCount = 0
                            Log.d(TAG, "Overlay kapatıldı.")
                        }
                    }
                }
            }
        }
    } else {
        // Filtre "Aile" ise overlay kesinlikle açık olmasın
        if (overlayVisible) {
            stopService(Intent(this, OverlayBlockerService::class.java))
            overlayVisible = false
            lastBlockedPkg = null
            nonBlockedEventCount = 0
            Log.d(TAG, "Filtre 'Aile', overlay kapatıldı.")
        }
        // Ayrıca başka hiçbir engelleme yapılmaz!
    }
}

    override fun onInterrupt() {
        Log.w(TAG, "onInterrupt: Erişilebilirlik servisi KESİLDİ!")
    }

    override fun onDestroy() {
        super.onDestroy()
        firestoreListenerRegistration?.remove()
        firestoreListenerRegistration = null
    }
}
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
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

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

    private var blockedAppsWithUntil: Map<String, LocalDateTime> = emptyMap()
    private var overlayVisible = false
    private var lastBlockedPkg: String? = null
    private var nonBlockedEventCount = 0
    private var userId: String? = null
    private var firestoreListenerRegistration: ListenerRegistration? = null

    override fun onServiceConnected() {
        Log.i(TAG, "onServiceConnected: Erişilebilirlik servisi BAŞLADI.")

        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPES_ALL_MASK
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.notificationTimeout = 100
        serviceInfo = info

        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val anyUserId = prefs.all["flutter.user_id"]
        userId = when (anyUserId) {
            is String -> anyUserId
            is Long -> anyUserId.toString()
            is Int -> anyUserId.toString()
            else -> null
        }
        listenBlockedAppsFromFirebase()
    }

    private fun resolvePackageNameFromAppName(appName: String): String? {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN, null)
        intent.addCategory(Intent.CATEGORY_LAUNCHER)
        val allApps = pm.queryIntentActivities(intent, 0)
        for (app in allApps) {
            val label = app.loadLabel(pm).toString().trim().lowercase()
            if (label == appName.trim().lowercase()) {
                return app.activityInfo.packageName
            }
        }
        return null
    }

    private fun listenBlockedAppsFromFirebase() {
        val uid = userId
        if (uid == null) {
            blockedAppsWithUntil = emptyMap()
            firestoreListenerRegistration?.remove()
            firestoreListenerRegistration = null
            return
        }
        val docId = uid
        val firestore = FirebaseFirestore.getInstance()
        firestoreListenerRegistration?.remove()
        firestoreListenerRegistration = firestore.collection("user_usagestats")
            .document(docId)
            .addSnapshotListener { doc, error ->
                if (error != null) {
                    blockedAppsWithUntil = emptyMap()
                    return@addSnapshotListener
                }
                if (doc != null && doc.exists()) {
                    val restrictedApps = doc.get("restricted_apps") as? List<*>
                    val now = LocalDateTime.now(ZoneId.systemDefault())
                    blockedAppsWithUntil = restrictedApps
                        ?.mapNotNull { entry ->
                            if (entry is Map<*, *>) {
                                val appName = entry["appName"]?.toString() ?: return@mapNotNull null
                                val untilStr = entry["until"]?.toString()
                                if (untilStr == null) return@mapNotNull null
                                val untilDate = try {
                                    LocalDateTime.parse(untilStr, DateTimeFormatter.ISO_DATE_TIME)
                                } catch (e: Exception) {
                                    null
                                }
                                // until şimdiden önce ise engellenmiş say
                                if (untilDate != null && now.isAfter(untilDate)) {
                                    val pkg = if (appName.startsWith("com.")) appName else resolvePackageNameFromAppName(appName)
                                    if (pkg != null) pkg to untilDate else null
                                } else null
                            } else null
                        }
                        ?.toMap() ?: emptyMap()
                } else {
                    blockedAppsWithUntil = emptyMap()
                }
            }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val eventType = event.eventType
        val pkg = event.packageName?.toString() ?: return

        if (eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            when {
                blockedAppsWithUntil.containsKey(pkg) -> {
                    if (!overlayVisible) {
                        Handler(Looper.getMainLooper()).post {
                            Toast.makeText(
                                this,
                                "3 saniye içinde uygulamadan çıkılacak!",
                                Toast.LENGTH_SHORT
                            ).show()
                        }
                        Handler(Looper.getMainLooper()).postDelayed({
                            if (Settings.canDrawOverlays(this)) {
                                startService(Intent(this, OverlayBlockerService::class.java))
                                overlayVisible = true
                                Handler(Looper.getMainLooper()).postDelayed({
                                    Toast.makeText(
                                        this,
                                        "Ebeveyniniz tarafından uygulamaya girişiniz engellenmiştir.",
                                        Toast.LENGTH_LONG
                                    ).show()
                                }, 1000)
                            } else {
                                Toast.makeText(
                                    this,
                                    "Lütfen uygulama için 'Diğer uygulamaların üstünde göster' iznini verin.",
                                    Toast.LENGTH_LONG
                                ).show()
                            }
                        }, 3000)
                    }
                    lastBlockedPkg = pkg
                    nonBlockedEventCount = 0
                }
                systemPackages.contains(pkg) -> { }
                else -> {
                    if (overlayVisible && lastBlockedPkg != null) {
                        nonBlockedEventCount++
                        if (nonBlockedEventCount >= 2) {
                            stopService(Intent(this, OverlayBlockerService::class.java))
                            overlayVisible = false
                            lastBlockedPkg = null
                            nonBlockedEventCount = 0
                        }
                    }
                }
            }
        }
    }

    override fun onInterrupt() {}
    override fun onDestroy() {
        super.onDestroy()
        firestoreListenerRegistration?.remove()
        firestoreListenerRegistration = null
    }
}
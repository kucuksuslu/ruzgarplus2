package com.example.ruzgarplus

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import androidx.annotation.NonNull
import android.content.pm.PackageManager
import android.app.AppOpsManager
import android.provider.Settings
import android.content.Intent
import android.net.Uri
import com.example.ruzgarplus.AgoraForegroundService
import android.util.Log
import android.Manifest
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.app/usage_stats"
    private val OVERLAY_CHANNEL = "com.example.ruzgarplus/overlay"
    private val NATIVE_SERVICE_CHANNEL = "com.example.ruzgarplus/native"
    private val AGORA_CHANNEL = "com.example.ruzgarplus/agora_service"

    private val PERMISSION_REQUEST_CODE = 4321

    // Pending intent to start Agora service after permission
    private var pendingAgoraIntent: Intent? = null

    // GEREKLİ TÜM FOREGROUND SERVICE/MIC PERMISSION DİZİSİ (Android 14+ mikrofon/kamera için zorunlu!)
    private val REQUIRED_PERMISSIONS = if (Build.VERSION.SDK_INT >= 34) arrayOf(
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.FOREGROUND_SERVICE_MICROPHONE,
        Manifest.permission.FOREGROUND_SERVICE
    ) else arrayOf(
        Manifest.permission.RECORD_AUDIO,
        Manifest.permission.FOREGROUND_SERVICE
    )

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d("MainActivity", "configureFlutterEngine ÇALIŞTI.")

        // Uygulama açılır açılmaz izinleri kontrol et ve iste
        ensureMicrophonePermissionsIfNeeded()
         // uygulama resim alma 
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    .setMethodCallHandler { call, result ->
        when (call.method) {
       "getAppIcon" -> {
    val packageName = call.argument<String>("packageName")
    Log.d("GET_APP_ICON", "İkon alınmak istenen package: $packageName")
    try {
        val pm = packageManager
        val icon = pm.getApplicationIcon(packageName!!)
        Log.d("GET_APP_ICON", "Application icon bulundu: $packageName (${icon.javaClass.simpleName})")
        val drawable = icon
        val bitmap = when (drawable) {
            is BitmapDrawable -> drawable.bitmap
            is android.graphics.drawable.AdaptiveIconDrawable -> {
                val width = drawable.intrinsicWidth
                val height = drawable.intrinsicHeight
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                bitmap
            }
            else -> null
        }
        if (bitmap != null) {
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            result.success(stream.toByteArray())
            Log.d("GET_APP_ICON", "Bitmap başarıyla döndü: $packageName")
        } else {
            Log.e("GET_APP_ICON", "Drawable bitmap değil: $packageName (${icon.javaClass.simpleName})")
            result.success(null)
        }
    } catch (e: Exception) {
        Log.e("GET_APP_ICON", "Hata oluştu: $packageName (${e.javaClass.simpleName}): ${e.message}", e)
        result.success(null)
    }
}

            // Yeni yöntem: uygulama adı (label) ile package name bul ve ikon döndür
            "getAppIconFromLabel" -> {
                val appLabelRaw = call.argument<String>("appLabel") ?: ""
                val appLabel = appLabelRaw.trim().lowercase()
                try {
                    val pm = packageManager
                    val apps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    var foundPackageName: String? = null

                    // 1. Tam eşleşme (küçük/büyük harf ve boşluk duyarsız)
                    for (app in apps) {
                        val label = pm.getApplicationLabel(app).toString().trim().lowercase()
                        if (label == appLabel) {
                            foundPackageName = app.packageName
                            break
                        }
                    }

                    // 2. Boşlukları kaldırarak tam eşleşme
                    if (foundPackageName == null) {
                        val appLabelNoSpace = appLabel.replace("\\s".toRegex(), "")
                        for (app in apps) {
                            val label = pm.getApplicationLabel(app).toString().trim().lowercase()
                            val labelNoSpace = label.replace("\\s".toRegex(), "")
                            if (labelNoSpace == appLabelNoSpace) {
                                foundPackageName = app.packageName
                                break
                            }
                        }
                    }

                    // 3. Kısmi eşleşme (içinde geçiyorsa)
                    if (foundPackageName == null) {
                        for (app in apps) {
                            val label = pm.getApplicationLabel(app).toString().trim().lowercase()
                            if (label.contains(appLabel)) {
                                foundPackageName = app.packageName
                                break
                            }
                        }
                    }

                    // 4. Boşlukları kaldırıp kısmi eşleşme
                    if (foundPackageName == null) {
                        val appLabelNoSpace = appLabel.replace("\\s".toRegex(), "")
                        for (app in apps) {
                            val label = pm.getApplicationLabel(app).toString().trim().lowercase()
                            val labelNoSpace = label.replace("\\s".toRegex(), "")
                            if (labelNoSpace.contains(appLabelNoSpace)) {
                                foundPackageName = app.packageName
                                break
                            }
                        }
                    }

                    if (foundPackageName != null) {
                        val icon = pm.getApplicationIcon(foundPackageName)
                        val bitmap = (icon as BitmapDrawable).bitmap
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                        result.success(stream.toByteArray())
                    } else {
                        // Debug için: logcat'e uygulama adlarını yaz
                        val allLabels = apps.map { pm.getApplicationLabel(it).toString() + " [${it.packageName}]" }
                        android.util.Log.d("APP_ICON_DEBUG", "NOT FOUND: $appLabelRaw. Device apps: $allLabels")
                        result.success(null)
                    }
                } catch (e: Exception) {
                    result.success(null)
                }
            }
            // Diğer methodlar burada devam edebilir...
        }
    }
        // OVERLAY KANALI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("OverlayChannel", "Overlay channel method: ${call.method}")
            when (call.method) {
                "checkOverlayPermission" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    Log.d("OverlayChannel", "Overlay izni durumu: $canDraw")
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
                    Log.d("OverlayChannel", "Overlay izni isteniyor.")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    Log.w("OverlayChannel", "Bilinmeyen method: ${call.method}")
                    result.notImplemented()
                }
            }
        }

        // AGORA ARKA PLAN CANLI YAYIN KANALI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGORA_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("AgoraChannel", "MethodChannel tetiklendi! Method: ${call.method}")
            when (call.method) {
                "startAgoraListening" -> {
                    Log.d("AgoraChannel", "startAgoraListening çağrıldı")
                    val userId = call.argument<String>("userId") ?: "12345"
                    val userType = call.argument<String>("userType") ?: ""
                     val firebaseUid = call.argument<String>("firebase_uid")
                    // roomId parametresi yoksa userId + "room" olarak oluştur
                    val roomId = call.argument<String>("roomId") ?: (userId + "room")
                    val role = call.argument<String>("role") ?: "audience"
                    val otherUserId = call.argument<String>("otherUserId")
                    Log.d("AgoraChannel", "Parametreler -> userId: $userId, user_type: $userType, roomId: $roomId, role: $role, otherUserId: $otherUserId")

                    val intent = Intent(this, AgoraForegroundService::class.java)
                    intent.putExtra("roomId", roomId)
                    intent.putExtra("userId", userId)
                     intent.putExtra("firebase_uid", firebaseUid)
                    intent.putExtra("user_type", userType) // userType doğru key ile eklendi
                    intent.putExtra("role", role)
                    intent.putExtra("otherUserId", otherUserId)

                    if (hasAllPermissions()) {
                        Log.d("AgoraChannel", "Tüm izinler var, servis başlatılıyor")
                        startAgoraService(intent)
                        result.success("Başlatıldı")
                    } else {
                        Log.d("AgoraChannel", "İzinler eksik, izin isteniyor, pending intent tutuluyor.")
                        pendingAgoraIntent = intent
                        requestAllPermissions()
                        // result.success burada çağrılmaz, izin sonucu callback'te handle edilir!
                    }
                }
                "stopAgoraListening" -> {
                    Log.d("AgoraChannel", "stopAgoraListening çağrıldı")
                    val intent = Intent(this, AgoraForegroundService::class.java)
                    stopService(intent)
                    result.success("Durduruldu")
                }
                else -> {
                    Log.w("AgoraChannel", "Bilinmeyen method: ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    // Uygulama ilk başlarken veya servisten önce kesin yetki kontrolü için
    private fun ensureMicrophonePermissionsIfNeeded() {
        val notGranted = REQUIRED_PERMISSIONS.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        Log.d("MainActivity", "İlk izin kontrolü, eksik izinler: $notGranted")
        if (notGranted.isNotEmpty()) {
            Log.d("MainActivity", "Eksik izin(ler) isteniyor: $notGranted")
            ActivityCompat.requestPermissions(this, notGranted.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    // Tüm gerekli izinleri kontrol et
    private fun hasAllPermissions(): Boolean {
        val result = REQUIRED_PERMISSIONS.all {
            val granted = ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
            Log.d("MainActivity", "İzin kontrolü: $it -> $granted")
            granted
        }
        Log.d("MainActivity", "Tüm izinler var mı? $result")
        return result
    }

    // Gerekli izinleri iste
    private fun requestAllPermissions() {
        Log.d("MainActivity", "Tüm gerekli izinler isteniyor: ${REQUIRED_PERMISSIONS.toList()}")
        ActivityCompat.requestPermissions(this, REQUIRED_PERMISSIONS, PERMISSION_REQUEST_CODE)
    }

    // İzin sonucu callback
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        Log.d("MainActivity", "onRequestPermissionsResult: code=$requestCode, permissions=${permissions.toList()}, grantResults=${grantResults.toList()}")
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (hasAllPermissions()) {
                Log.d("MainActivity", "Tüm izinler verildi, pending intent var mı? ${pendingAgoraIntent != null}")
                pendingAgoraIntent?.let {
                    Log.d("MainActivity", "Agora servisini başlatıyoruz (pendingIntent)")
                    startAgoraService(it)
                    pendingAgoraIntent = null
                }
            } else {
                Log.e("MainActivity", "Kullanıcı gerekli tüm izinleri vermedi.")
            }
        }
    }

    // Agora servisini başlat
    private fun startAgoraService(intent: Intent) {
        Log.d("MainActivity", "startAgoraService çağrıldı. intent: $intent, extras: ${intent.extras}")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.d("MainActivity", "startForegroundService ile başlatılıyor.")
            startForegroundService(intent)
        } else {
            Log.d("MainActivity", "startService ile başlatılıyor.")
            startService(intent)
        }
    }

    // Kullanım istatistiği izni kontrolü
    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            Log.d("MainActivity", "UsageStats permission mode: $mode")
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e("MainActivity", "UsageStats permission kontrolünde hata: ${e.message}", e)
            false
        }
    }
}
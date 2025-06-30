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

        // Uygulama açılır açılmaz izinleri kontrol et ve iste
        ensureMicrophonePermissionsIfNeeded()

   

        // OVERLAY KANALI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVERLAY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }
                "requestOverlayPermission" -> {
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
                else -> result.notImplemented()
            }
        }

      

        // AGORA ARKA PLAN CANLI YAYIN KANALI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AGORA_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("AgoraChannel", "MethodChannel tetiklendi! Method: ${call.method}")
            when (call.method) {
                "startAgoraListening" -> {
                    Log.d("AgoraChannel", "startAgoraListening çağrıldı")
                    val roomId = call.argument<String>("roomId") ?: "Aile_12345"
                    val userId = call.argument<String>("userId") ?: "12345"
                    val role = call.argument<String>("role") ?: "audience"
                    val userFilter = call.argument<String>("userFilter") // ← EKLE
                    val intent = Intent(this, AgoraForegroundService::class.java)
                    intent.putExtra("roomId", roomId)
                    intent.putExtra("userId", userId)
                    intent.putExtra("role", role)
                    intent.putExtra("userFilter", userFilter)  

                    if (hasAllPermissions()) {
                        Log.d("AgoraChannel", "Tüm izinler var, servis başlatılıyor")
                        startAgoraService(intent)
                        result.success("Başlatıldı")
                    } else {
                        Log.d("AgoraChannel", "İzinler eksik, izin isteniyor")
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
                    Log.d("AgoraChannel", "Bilinmeyen method: ${call.method}")
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
        if (notGranted.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, notGranted.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    // Tüm gerekli izinleri kontrol et
    private fun hasAllPermissions(): Boolean {
        return REQUIRED_PERMISSIONS.all {
            ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    // Gerekli izinleri iste
    private fun requestAllPermissions() {
        ActivityCompat.requestPermissions(this, REQUIRED_PERMISSIONS, PERMISSION_REQUEST_CODE)
    }

    // İzin sonucu callback
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            if (hasAllPermissions()) {
                pendingAgoraIntent?.let {
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
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
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }
}
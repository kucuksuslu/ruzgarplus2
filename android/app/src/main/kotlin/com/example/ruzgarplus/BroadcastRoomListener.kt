package com.example.ruzgarplus

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.content.pm.PackageManager
import android.media.AudioManager
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

class BroadcastRoomListener(
    private val context: Context
) {
    private var firestoreListener: ListenerRegistration? = null

    private fun forceAudioOpen(audioManager: AudioManager) {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = true
        try {
            audioManager.isMicrophoneMute = false
        } catch (e: Exception) {
            try {
                audioManager.setMicrophoneMute(false)
            } catch (_: Exception) {}
        }
        // Ekstra: Tüm stream'lerin sesini aç (kullanıcı yanlışlıkla kapatmasın diye)
        audioManager.setStreamMute(AudioManager.STREAM_MUSIC, false)
        audioManager.setStreamMute(AudioManager.STREAM_VOICE_CALL, false)
        audioManager.setStreamMute(AudioManager.STREAM_SYSTEM, false)
        Log.d("BroadcastRoomListener", "[DEBUG] forceAudioOpen: Hoparlör ve mikrofon açıldı, mute kapalı")
    }

    fun startListening() {
        Log.d("BroadcastRoomListener", "[DEBUG] startListening() çağrıldı")
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val myUserId: String? = prefs.all["flutter.user_id"]?.toString()
        Log.d("BroadcastRoomListener", "[DEBUG] myUserId: $myUserId")
        if (myUserId.isNullOrEmpty()) {
            Log.e("BroadcastRoomListener", "[DEBUG] myUserId bulunamadı!")
            return
        }

        val db = FirebaseFirestore.getInstance()
        Log.d("BroadcastRoomListener", "[DEBUG] Firestore dinleyici kuruluyor: otherUserId=$myUserId")
        firestoreListener = db.collection("active_audio_rooms")
            .whereEqualTo("otherUserId", myUserId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    Log.e("BroadcastRoomListener", "[DEBUG] Firestore dinleme hatası: ${error.message}")
                    return@addSnapshotListener
                }
                if (snapshot == null || snapshot.isEmpty) {
                    Log.d("BroadcastRoomListener", "[DEBUG] Snapshot boş, aktif oda yok.")
                    // Oda yokken bile ses ayarlarını açık tut
                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    forceAudioOpen(audioManager)
                    return@addSnapshotListener
                }

                Log.d("BroadcastRoomListener", "[DEBUG] Oda(lar) bulundu: ${snapshot.documents.size} adet")
                for (doc in snapshot.documents) {
                    val data = doc.data ?: continue
                    val roomId = data["roomId"]?.toString() ?: doc.id
                    val userIdFromMsg = data["userId"]?.toString() ?: ""
                    val status = data["status"]?.toString() ?: ""
                    val otherUserId = data["otherUserId"]?.toString() ?: ""

                    Log.d("BroadcastRoomListener", "[DEBUG] roomId=$roomId, userIdFromMsg=$userIdFromMsg, status=$status, otherUserId=$otherUserId")

                    if (myUserId == otherUserId) {
                        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

                        // Her durumda hoparlör ve mikrofonu açık tut!
                        forceAudioOpen(audioManager)

                        if (status == "active") {
                            if (context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                Log.e("BroadcastRoomListener", "[DEBUG] Mikrofon izni yok! Agora servisi başlatılmadı.")
                                continue
                            }
                            Log.d("BroadcastRoomListener", "[DEBUG] BROADCASTER: Yayıncı bu cihaz! Servis başlatılıyor...")
                            val intent = Intent(context, AgoraForegroundService::class.java)
                            intent.putExtra("userId", myUserId)
                            intent.putExtra("role", "broadcaster")
                            intent.putExtra("roomId", roomId)
                            intent.putExtra("otherUserId", userIdFromMsg)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                context.startForegroundService(intent)
                            } else {
                                context.startService(intent)
                            }
                        } else if (status == "passive") {
                            // Servisi durdur!
                            Log.d("BroadcastRoomListener", "[DEBUG] PASSIVE oda bulundu! Agora servisi durduruluyor...")
                            val stopIntent = Intent(context, AgoraForegroundService::class.java)
                            context.stopService(stopIntent)
                        }
                    }
                }
            }
    }

    fun stopListening() {
        Log.d("BroadcastRoomListener", "[DEBUG] stopListening() çağrıldı")
        firestoreListener?.remove()
        firestoreListener = null
    }
}
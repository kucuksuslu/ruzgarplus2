package com.example.ruzgarplus

import android.app.*
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.firestore.*
import io.agora.rtc2.*
import android.content.pm.ServiceInfo

class AgoraForegroundService : Service() {
    private var agoraEngine: RtcEngine? = null
    private val appId = "8109382d3cde4ef881a8fb846237f2ed"
    private val token: String? = null

    private var roomId: String? = null
    private var userId: String? = null
    private var role: String? = null

    private var isJoined = false
    private var docListener: ListenerRegistration? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("AgoraService", "onStartCommand called, intent = $intent")

        // Foreground notification HER DURUMDA en başta başlatılmalı!
        try {
            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    1, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(1, notification)
            }
            Log.d("AgoraService", "Foreground notification başlatıldı")
        } catch (e: Exception) {
            Log.e("AgoraService", "Notification başlatılamadı: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }

        // Intent parametreleriyle durumu güncelle
        if (roomId == null) {
            roomId = intent?.getStringExtra("roomId") ?: "room_001"
            userId = intent?.getStringExtra("userId") ?: "123456"
            val userFilter = intent?.getStringExtra("userFilter") ?: ""
            // userFilter kontrolü: Eğer Aile değilse broadcaster, Aile ise dinleyici
            role = if (userFilter != "Aile") {
                "broadcaster"
            } else {
                "audience"
            }
            Log.d("AgoraService", "onStartCommand - roomId: $roomId, userId: $userId, userFilter: $userFilter, role: $role")

            initAgoraEngine()
            startFirestoreListener()
        } else {
            Log.d("AgoraService", "onStartCommand tekrar çağrıldı, roomId sabit: $roomId")
        }
        return START_STICKY
    }

    private fun startFirestoreListener() {
        Log.d("AgoraService", "startFirestoreListener called")
        val rId = roomId ?: run {
            Log.e("AgoraService", "startFirestoreListener: roomId null, listener başlatılamadı")
            return
        }
        val db = FirebaseFirestore.getInstance()
        val docRef = db.collection("active_audio_rooms").document(rId)
        docListener?.remove()
        Log.d("AgoraService", "Firestore listener başlatılıyor, docRef=$docRef")

        docListener = docRef.addSnapshotListener { snapshot, error ->
            Log.d("AgoraService", "Firestore snapshotListener tetiklendi")
            if (error != null) {
                Log.e("AgoraService", "Firestore error: $error")
                return@addSnapshotListener
            }
            if (snapshot == null || !snapshot.exists()) {
                Log.w("AgoraService", "Firestore snapshot null veya yok!")
                return@addSnapshotListener
            }
            val data = snapshot.data
            val status = data?.get("status") as? String ?: ""
            val docRoomId = data?.get("roomID") as? String ?: ""
            val docUserId = data?.get("userID") as? String ?: ""

            Log.d("AgoraService", "[SNAPSHOT] status=$status, roomID=$docRoomId, userID=$docUserId, localRoomID=$roomId, localUserID=$userId, isJoined=$isJoined")

            if (docRoomId == roomId && docUserId == userId) {
                when {
                    status == "active" && !isJoined -> {
                        Log.d("AgoraService", "Status ACTIVE! joinChannel() çağrılacak")
                        joinChannel()
                    }
                    status == "closed" && isJoined -> {
                        Log.d("AgoraService", "Status CLOSED! leaveChannel() çağrılacak")
                        leaveChannel()
                    }
                    else -> {
                        Log.d("AgoraService", "Status değişimi ama işlem gerekmiyor (status: $status, isJoined: $isJoined)")
                    }
                }
            } else {
                Log.d("AgoraService", "Snapshot kendi odası değil veya kullanıcıya ait değil. (docRoomId=$docRoomId, docUserId=$docUserId)")
            }
        }
    }

    private fun createNotification(): Notification {
        Log.d("AgoraService", "createNotification() çağrıldı")

        val channelId = "agora_channel"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Log.d("AgoraService", "Bildirim kanalı oluşturuluyor")
            val channel = NotificationChannel(
                channelId,
                "Agora Foreground",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Canlı Yayın (Otomatik)")
            .setContentText("Arka planda oda: $roomId dinleniyor")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .build()

        Log.d("AgoraService", "Notification başarıyla oluşturuldu")
        return notification
    }

    private fun initAgoraEngine() {
        Log.d("AgoraService", "initAgoraEngine called")
        try {
            if (agoraEngine == null) {
                agoraEngine = RtcEngine.create(
                    applicationContext,
                    appId,
                    object : IRtcEngineEventHandler() {
                        override fun onJoinChannelSuccess(channel: String?, uid: Int, elapsed: Int) {
                            Log.d("AgoraService", "[AGORA] Join success: $channel, uid: $uid")
                            isJoined = true
                        }
                        override fun onLeaveChannel(stats: RtcStats?) {
                            super.onLeaveChannel(stats)
                            isJoined = false
                            Log.d("AgoraService", "[AGORA] Left channel")
                        }
                        override fun onError(err: Int) {
                            Log.e("AgoraService", "[AGORA] Agora error: $err")
                        }
                    }
                )
                Log.d("AgoraService", "AgoraEngine başarıyla oluşturuldu")
            } else {
                Log.d("AgoraService", "agoraEngine zaten var")
            }
        } catch (e: Exception) {
            Log.e("AgoraService", "[AGORA] Agora Engine init error: ${e.message}", e)
        }
    }

private fun joinChannel() {
    Log.d("AgoraService", "joinChannel() çağrıldı")
    try {
        agoraEngine?.setChannelProfile(Constants.CHANNEL_PROFILE_LIVE_BROADCASTING)
        val clientRole = if (role == "broadcaster") {
            Constants.CLIENT_ROLE_BROADCASTER
        } else {
            Constants.CLIENT_ROLE_AUDIENCE
        }
        agoraEngine?.setClientRole(clientRole)

        // Mikrofon kontrolü
        if (role == "broadcaster") {
            agoraEngine?.muteLocalAudioStream(false)
            Log.d("AgoraService", "Broadcaster: Mikrofon AÇIK (muteLocalAudioStream(false))")
        } else {
            agoraEngine?.muteLocalAudioStream(true)
            Log.d("AgoraService", "Audience: Mikrofon KAPALI (muteLocalAudioStream(true))")
        }

        // HOPARLÖRÜ AÇ
        agoraEngine?.setEnableSpeakerphone(true)
        Log.d("AgoraService", "Hoparlör aktif edildi (setEnableSpeakerphone(true))")

        // userId ve userFilter birleştir, hashle ve int'e çevir
        val combinedId = (userId ?: "") + "_" + (role ?: "") // userFilter yerine role kullandın çünkü filtreye göre rol atanıyor
        val uidInt = combinedId.hashCode().let { if (it < 0) -it else it } // Pozitif integer

        Log.d("AgoraService", "[AGORA] Kullanıcı UID: $uidInt (combinedId: $combinedId)")

        agoraEngine?.joinChannel(token, roomId, "", uidInt)
        Log.d("AgoraService", "[AGORA] joinChannel called: $roomId, $userId (uid: $uidInt), role: $role")
    } catch (e: Exception) {
        Log.e("AgoraService", "[AGORA] joinChannel error: ${e.message}", e)
    }
}
    private fun leaveChannel() {
        Log.d("AgoraService", "leaveChannel() çağrıldı")
        try {
            agoraEngine?.leaveChannel()
            Log.d("AgoraService", "[AGORA] leaveChannel called")
        } catch (e: Exception) {
            Log.e("AgoraService", "[AGORA] leaveChannel error: ${e.message}", e)
        }
    }

  override fun onDestroy() {
    Log.d("AgoraService", "onDestroy called")
    leaveChannel()
    docListener?.remove()
    RtcEngine.destroy()
    agoraEngine = null

    // Oda status closed yap
    try {
        if (roomId != null && userId != null) {
            val db = FirebaseFirestore.getInstance()
            val docRef = db.collection("active_audio_rooms").document(roomId!!)
            docRef.update("status", "closed")
            Log.d("AgoraService", "Firestore: Oda status CLOSED yapıldı")
        }
    } catch (e: Exception) {
        Log.e("AgoraService", "Firestore status closed yapılamadı: ${e.message}")
    }
    super.onDestroy()
}

    override fun onBind(intent: Intent?): IBinder? = null
}
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
    private var userType: String? = null
    private var firebaseUid: String? = null

    private var isJoined = false
    private var docListener: ListenerRegistration? = null

    // Kullanıcı listesi (uid, role, userType)
    private val joinedUsers = mutableListOf<JoinedUser>()

    data class JoinedUser(val uid: Int, val role: String, val userType: String?)

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
            userType = intent?.getStringExtra("userType") ?: ""
            firebaseUid = intent?.getStringExtra("firebase_uid") ?: ""

            // user_type kontrolü: Eğer Aile değilse broadcaster, Aile ise dinleyici
            role = if (userType != "Aile") {
                "broadcaster"
            } else {
                "audience"
            }
            Log.d(
                "AgoraService",
                "onStartCommand - roomId: $roomId, userId: $userId, user_type: $userType, firebase_uid: $firebaseUid, role: $role"
            )

            initAgoraEngine()
            startFirestoreListener()
        } else {
            Log.d(
                "AgoraService",
                "onStartCommand tekrar çağrıldı, roomId sabit: $roomId,user_type: $userType"
            )
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

            Log.d(
                "AgoraService",
                "[SNAPSHOT] status=$status, roomID=$docRoomId, userID=$docUserId, localRoomID=$roomId, localUserID=$userId, isJoined=$isJoined"
            )

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
                        Log.d(
                            "AgoraService",
                            "Status değişimi ama işlem gerekmiyor (status: $status, isJoined: $isJoined)"
                        )
                    }
                }
            } else {
                Log.d(
                    "AgoraService",
                    "Snapshot kendi odası değil veya kullanıcıya ait değil. (docRoomId=$docRoomId, docUserId=$docUserId)"
                )
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
                            // Katılan kullanıcıyı listeye ekle
                            joinedUsers.add(JoinedUser(uid, role ?: "unknown", userType))
                            logJoinedUsers()
                        }

                        override fun onUserJoined(uid: Int, elapsed: Int) {
                            Log.d("AgoraService", "[AGORA] Başka kullanıcı katıldı: uid=$uid")
                            // Burada rol bilgisi yok, sadece uid var
                            // Listeye ekle (rol ve userType bilinmiyor)
                            joinedUsers.add(JoinedUser(uid, "unknown", null))
                            logJoinedUsers()
                        }

                        override fun onUserOffline(uid: Int, reason: Int) {
                            Log.d("AgoraService", "[AGORA] Kullanıcı ayrıldı: uid=$uid")
                            // Listeden çıkar
                            joinedUsers.removeAll { it.uid == uid }
                            logJoinedUsers()
                        }

                        override fun onLeaveChannel(stats: RtcStats?) {
                            super.onLeaveChannel(stats)
                            isJoined = false
                            Log.d("AgoraService", "[AGORA] Left channel")
                            joinedUsers.clear()
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

    private fun logJoinedUsers() {
        val listString = joinedUsers.joinToString(separator = "\n") {
            "UID: ${it.uid}, Role: ${it.role}, UserType: ${it.userType ?: "-"}"
        }
        Log.d(
            "AgoraService",
            "=== KANALDAKİ KULLANICILAR ===\n$listString\n=============================="
        )
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
      
            agoraEngine?.setEnableSpeakerphone(true)
            Log.d("AgoraService", "Hoparlör aktif edildi (setEnableSpeakerphone(true))")

            // UID üretimi: firebase_uid hashCode kullanılıyor, yoksa userId kullanılır
            val uidInt = (firebaseUid ?: userId ?: "").hashCode().let { if (it < 0) -it else it }

            Log.d(
                "AgoraService",
                "[AGORA] Kullanıcı UID: $uidInt (firebase_uid: $firebaseUid, role: $role, userType: $userType, userId: $userId)"
            )

            agoraEngine?.joinChannel(token, roomId, "", uidInt)
            Log.d(
                "AgoraService",
                "[AGORA] joinChannel called: $roomId, $userId (uid: $uidInt), role: $role"
            )
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
            val db = FirebaseFirestore.getInstance()
            val docRef = db.collection("active_audio_rooms").document(roomId!!)
            docRef.update("status", "closed")
            Log.d("AgoraService", "Firestore: Oda status CLOSED yapıldı")
        } catch (e: Exception) {
            Log.e("AgoraService", "Firestore status closed yapılamadı: ${e.message}")
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
package com.example.ruzgarplus

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        Log.d("FCM", "onMessageReceived: ${remoteMessage.data}")

        // Agora başlatma mesajı geldiyse foreground servisi başlat!
        if (remoteMessage.data["type"] == "agora_start") {
            val roomId = remoteMessage.data["roomId"] ?: return
            val userId = remoteMessage.data["userId"] ?: return
            val role = remoteMessage.data["role"] ?: "audience"
            val otherUserId = remoteMessage.data["otherUserId"] ?: ""
            val userType = remoteMessage.data["userType"] ?: "" // <-- userType eklendi

            // Foreground servis başlat!
            val intent = Intent(this, AgoraForegroundService::class.java)
            intent.putExtra("roomId", roomId)
            intent.putExtra("userId", userId)
            intent.putExtra("role", role)
            intent.putExtra("otherUserId", otherUserId)
            intent.putExtra("userType", userType) // <-- userType intent'e eklendi
            startForegroundServiceCompat(this, intent)
        }
    }

    private fun startForegroundServiceCompat(context: Context, intent: Intent) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
}
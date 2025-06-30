package com.example.ruzgarplus

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.view.*
import android.widget.FrameLayout
import android.widget.TextView
import android.view.animation.AlphaAnimation

class OverlayBlockerService : Service() {
    private var overlayView: View? = null
    private var isOverlayShown = false
    private val countdownSeconds = 3  // Geri sayım süresi

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (!isOverlayShown) {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.TOP or Gravity.START

            val overlay = FrameLayout(this)
            overlay.setBackgroundColor(0xCC000000.toInt())

            // Geri sayım için TextView
            val countdownView = TextView(this)
            countdownView.setTextColor(0xFFFFFFFF.toInt())
            countdownView.textSize = 48f
            countdownView.gravity = Gravity.CENTER
            overlay.addView(countdownView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ))

            // Ana mesaj için TextView (ilk başta görünmez)
            val blockTextView = TextView(this)
            blockTextView.text = "Bu uygulama engellenmiştir!"
            blockTextView.setTextColor(0xFFFFFFFF.toInt())
            blockTextView.textSize = 28f
            blockTextView.gravity = Gravity.CENTER
            blockTextView.visibility = View.INVISIBLE
            overlay.addView(blockTextView, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            ))

            // Dokunuşları tamamen engelle
            overlay.setOnTouchListener { _, _ -> true }

            try {
                wm.addView(overlay, params)
                isOverlayShown = true
                overlayView = overlay
            } catch (e: Exception) {
                // View zaten eklenmiş olabilir, yoksay
            }

            // Geri sayım animasyonunu başlat
            startCountdown(countdownView, blockTextView)
        }
    }

    private fun startCountdown(countdownView: TextView, blockTextView: TextView) {
        var secondsLeft = countdownSeconds
        val handler = Handler(mainLooper)

        val countdownRunnable = object : Runnable {
            override fun run() {
                if (secondsLeft > 0) {
                    // Fade in/fade out animasyon
                    countdownView.text = secondsLeft.toString()
                    val anim = AlphaAnimation(0.3f, 1.0f)
                    anim.duration = 250
                    countdownView.startAnimation(anim)

                    secondsLeft--
                    handler.postDelayed(this, 1000)
                } else {
                    // Geri sayım bitti, ana mesajı göster
                    countdownView.visibility = View.GONE
                    blockTextView.visibility = View.VISIBLE

                    // Fade-in efekti
                    val showAnim = AlphaAnimation(0.0f, 1.0f)
                    showAnim.duration = 400
                    blockTextView.startAnimation(showAnim)
                }
            }
        }
        handler.post(countdownRunnable)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (overlayView != null) {
            val wm = getSystemService(WINDOW_SERVICE) as WindowManager
            try {
                wm.removeView(overlayView)
            } catch (e: Exception) {
                // Zaten kaldırılmış olabilir
            }
            overlayView = null
            isOverlayShown = false
        }
    }
}
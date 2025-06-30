package com.example.ruzgarplus

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object FlutterBridge {
    private var channel: MethodChannel? = null

    fun init(context: Context) {
        if (channel == null) {
            val engine = FlutterEngine(context.applicationContext)
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.example.ruzgarplus/accessibility")
            engine.dartExecutor.executeDartEntrypoint(
                io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault()
            )
        }
    }

    fun sendAppDetected(pkg: String) {
        channel?.invokeMethod("onAppDetected", pkg)
    }
}
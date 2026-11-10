package com.example.toptop_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val VOLUME_CHANNEL = "vifarm/volume_channel"
    private val VOLUME_EVENTS = "vifarm/volume_events"
    private var volumeReceiver: BroadcastReceiver? = null
    private var volumeObserver: ContentObserver? = null

    private fun getVolumeInfo(audioManager: AudioManager?): Map<String, Any> {
        if (audioManager == null) {
            return mapOf("volume" to 10, "maxVolume" to 15, "isMuted" to false)
        }
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val isMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager.isStreamMute(AudioManager.STREAM_MUSIC) || currentVolume == 0
        } else {
            currentVolume == 0
        }
        return mapOf(
            "volume" to currentVolume,
            "maxVolume" to maxVolume,
            "isMuted" to isMuted
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> {
                    result.success(getVolumeInfo(audioManager))
                }
                "setMute" -> {
                    val mute = call.argument<Boolean>("mute") ?: false
                    audioManager?.let { am ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val flag = if (mute) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
                            am.adjustStreamVolume(AudioManager.STREAM_MUSIC, flag, 0)
                        }
                        if (!mute) {
                            val cur = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                            if (cur == 0) {
                                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                                am.setStreamVolume(AudioManager.STREAM_MUSIC, (max / 3).coerceAtLeast(1), 0)
                            }
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Send initial volume state immediately on listener attachment
                    events?.success(getVolumeInfo(audioManager))

                    val handler = Handler(Looper.getMainLooper())

                    // 1. ContentObserver captures hardware volume key presses on all Android versions
                    volumeObserver = object : ContentObserver(handler) {
                        override fun onChange(selfChange: Boolean) {
                            super.onChange(selfChange)
                            events?.success(getVolumeInfo(audioManager))
                        }
                    }
                    try {
                        contentResolver.registerContentObserver(
                            Settings.System.CONTENT_URI,
                            true,
                            volumeObserver!!
                        )
                    } catch (_: Exception) {}

                    // 2. BroadcastReceiver for system-wide volume changed broadcasts
                    volumeReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            events?.success(getVolumeInfo(audioManager))
                        }
                    }
                    val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            registerReceiver(volumeReceiver, filter, Context.RECEIVER_EXPORTED)
                        } else {
                            registerReceiver(volumeReceiver, filter)
                        }
                    } catch (_: Exception) {
                        try {
                            registerReceiver(volumeReceiver, filter)
                        } catch (_: Exception) {}
                    }
                }

                override fun onCancel(arguments: Any?) {
                    volumeObserver?.let {
                        try {
                            contentResolver.unregisterContentObserver(it)
                        } catch (_: Exception) {}
                        volumeObserver = null
                    }
                    volumeReceiver?.let {
                        try {
                            unregisterReceiver(it)
                        } catch (_: Exception) {}
                        volumeReceiver = null
                    }
                }
            }
        )
    }
}

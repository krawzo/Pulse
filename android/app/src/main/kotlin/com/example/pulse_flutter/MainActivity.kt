package com.example.pulse_flutter

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var multicastUsers = 0
    private var folderImporter: PulseFolderImporter? = null
    private var audioOutputObserver: PulseAudioOutputObserver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        folderImporter = PulseFolderImporter(this)
        audioOutputObserver = PulseAudioOutputObserver(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/mobile_folder")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> folderImporter?.pick(result)
                    "refresh" -> folderImporter?.refresh(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwakeForLyrics" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/network_status")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isUnmeteredLocal" -> {
                        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork)
                        result.success(capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true ||
                            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pulse/cast_discovery")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "acquire" -> {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("pulse_cast_discovery").apply {
                                    setReferenceCounted(false)
                                }
                            }
                            if (multicastUsers == 0) multicastLock?.acquire()
                            multicastUsers++
                            result.success(null)
                        }
                        "release" -> {
                            if (multicastUsers > 0 && --multicastUsers == 0 && multicastLock?.isHeld == true) {
                                multicastLock?.release()
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("MULTICAST_LOCK", error.message, null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        folderImporter?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (multicastLock?.isHeld == true) multicastLock?.release()
        multicastUsers = 0
        folderImporter?.dispose()
        folderImporter = null
        audioOutputObserver?.dispose()
        audioOutputObserver = null
        super.onDestroy()
    }
}

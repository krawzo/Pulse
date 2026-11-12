package com.example.pulse_flutter

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/** Reports connected external Android audio outputs to the mobile player. */
class PulseAudioOutputObserver(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var registered = false

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = emit()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = emit()
    }

    init {
        EventChannel(messenger, "pulse/audio_output").setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        events = eventSink
        if (!registered) {
            audioManager.registerAudioDeviceCallback(callback, mainHandler)
            registered = true
        }
        emit()
    }

    override fun onCancel(arguments: Any?) {
        dispose()
    }

    fun dispose() {
        if (registered) {
            audioManager.unregisterAudioDeviceCallback(callback)
            registered = false
        }
        events = null
    }

    private fun emit() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { emit() }
            return
        }
        events?.success(connectedOutputName())
    }

    private fun connectedOutputName(): String? {
        val output = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .mapNotNull { device ->
                val priority = when (device.type) {
                    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                    AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                    AudioDeviceInfo.TYPE_BLE_HEADSET,
                    AudioDeviceInfo.TYPE_BLE_SPEAKER -> 0
                    AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                    AudioDeviceInfo.TYPE_WIRED_HEADSET -> 1
                    AudioDeviceInfo.TYPE_USB_HEADSET,
                    AudioDeviceInfo.TYPE_USB_DEVICE,
                    AudioDeviceInfo.TYPE_USB_ACCESSORY -> 2
                    AudioDeviceInfo.TYPE_HDMI,
                    AudioDeviceInfo.TYPE_HDMI_ARC -> 3
                    else -> return@mapNotNull null
                }
                priority to device
            }
            .minByOrNull { it.first }
            ?.second ?: return null

        val name = output.productName?.toString()?.trim().orEmpty()
        if (name.isNotEmpty() && name != "null") return name
        return when (output.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER -> "Dispositivo Bluetooth"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Fones de ouvido"
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "Saída USB"
            else -> "Saída HDMI"
        }
    }
}

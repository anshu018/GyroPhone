package com.gyrophone.gyrophone

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.Executor

/**
 * The DS4 emulation core: registers the app as a Bluetooth HID device with the
 * DS4 SDP record, forwards input reports to the host, and surfaces host
 * requests to Dart.
 *
 * Threading: every Bluetooth call and every [BluetoothHidDevice.Callback]
 * invocation runs on a dedicated single-thread executor ([btExecutor]) — the
 * UI thread is never blocked and report ordering is preserved. Events reach
 * Flutter via [mainHandler] because the platform channel sinks are main-thread
 * only.
 *
 * Permissions: the Dart side calls [ensurePermissions] before anything else;
 * every method here still fails loudly (channel error) if [BLUETOOTH_CONNECT]
 * is missing — a silent failure here is exactly the bug class that costs days
 * on a real device (see docs/specs/M1-pair-as-ds4.md, Pitfalls).
 */
class HidPlugin(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "HidPlugin"
        private const val METHOD_CHANNEL = "gyrophone/hid"
        private const val EVENT_CHANNEL = "gyrophone/hid_events"

        // Event names shared with lib/hid/hid_bridge.dart.
        private const val EVENT_APP_STATUS = "appStatus"
        private const val EVENT_CONNECTION_STATE = "connectionState"
        private const val EVENT_HOST_REQUEST = "hostRequest"
        private const val EVENT_BT_STATE = "btState"

        private const val PERMISSION_REQUEST_CODE = 0x4750 // "GP"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val btThread = HandlerThread("gyrophone-hid").apply { start() }
    private val btHandler = Handler(btThread.looper)
    private val btExecutor = Executor { task -> btHandler.post(task) }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var hidDevice: BluetoothHidDevice? = null
    private var proxyRequested = false
    private var pendingRegisterSdp: BluetoothHidDeviceAppSdpSettings? = null

    /** Last input report 0x01 sent, kept so GET_REPORT(0x01) can be answered. */
    private var lastInputReport: ByteArray = ByteArray(Ds4Descriptors.INPUT_SMALL_PAYLOAD_SIZE)

    private var pendingPermissionResult: Result? = null
    private var activity: Activity? = null

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            logD("onAppStatusChanged registered=$registered host=${pluggedDevice?.address}")
            emit(EVENT_APP_STATUS) {
                mapOf("registered" to registered, "host" to pluggedDevice?.address)
            }
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            val stateName = connectionStateName(state)
            logD("onConnectionStateChanged ${device.address} -> $stateName")
            emit(EVENT_CONNECTION_STATE) {
                mapOf(
                    "address" to device.address,
                    "name" to deviceName(device),
                    "state" to stateName,
                )
            }
        }

        override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
            logD("onGetReport type=$type id=$id bufferSize=$bufferSize")
            if (type == BluetoothHidDevice.REPORT_TYPE_INPUT && id == Ds4Descriptors.REPORT_ID_INPUT_SMALL) {
                val reply = ByteArray(maxOf(bufferSize, lastInputReport.size))
                lastInputReport.copyInto(reply)
                hidDevice?.replyReport(device, type, id, reply)
            } else if (type == BluetoothHidDevice.REPORT_TYPE_FEATURE && id == Ds4Descriptors.FEATURE_ID_CALIBRATION) {
                // M1 replies with zeros; real calibration values are Step 2
                // (docs/specs/M1-pair-as-ds4.md R6). Windows never asks; a
                // Steam DS4 path would — the log entry is the evidence.
                hidDevice?.replyReport(device, type, id, ByteArray(maxOf(bufferSize, Ds4Descriptors.FEATURE_CALIBRATION_SIZE)))
            } else {
                logD("onGetReport unsupported: type=$type id=$id")
                hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_UNSUPPORTED_REQ)
            }
            emitHostRequest("getReport", type = type, id = id)
        }

        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            // Output reports arrive here (control channel) or via
            // onInterruptData (interrupt channel). M1 only records them; real
            // consumption is Step 2/5.
            logD("onSetReport type=$type id=$id length=${data.size}")
            hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            emitHostRequest("setReport", type = type, id = id, length = data.size)
        }

        override fun onInterruptData(device: BluetoothDevice, reportId: Byte, data: ByteArray) {
            // BT output report 0x11 (rumble) is expected here. The data array
            // excludes the report ID — the ID travels separately (verified in
            // the AOSP JNI layer; spec Pitfalls).
            logD("onInterruptData id=$reportId length=${data.size}")
            emitHostRequest("interruptData", id = reportId, length = data.size)
        }

        override fun onSetProtocol(device: BluetoothDevice, protocol: Byte) {
            // Report mode is assumed throughout; log only.
            logD("onSetProtocol protocol=$protocol")
            emitHostRequest("setProtocol", id = protocol)
        }

        override fun onVirtualCableUnplug(device: BluetoothDevice) {
            logD("onVirtualCableUnplug ${device.address}")
            emitHostRequest("vcUnplug")
        }
    }

    private val btStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            val state = when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> "on"
                BluetoothAdapter.STATE_OFF -> "off"
                BluetoothAdapter.STATE_TURNING_ON -> "turningOn"
                BluetoothAdapter.STATE_TURNING_OFF -> "turningOff"
                else -> return
            }
            logD("bt state -> $state")
            emit(EVENT_BT_STATE) { mapOf("state" to state) }
        }
    }

    init {
        methodChannel.setMethodCallHandler(::onMethodCall)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        ContextCompat.registerReceiver(
            context,
            btStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        btHandler.post {
            try {
                hidDevice?.unregisterApp()
            } catch (e: IllegalStateException) {
                // Proxy already gone (BT off / service died) — unregistering is
                // best-effort during teardown; state cannot regress further.
                Log.w(TAG, "unregisterApp during dispose failed", e)
            }
            hidDevice = null
        }
        context.unregisterReceiver(btStateReceiver)
        btThread.quitSafely()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val result = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        logD("permission result granted=$granted")
        result?.success(granted)
    }

    private fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "ensurePermissions" -> ensurePermissions(result)
            "register" -> btExecutor.execute { register(result) }
            "unregister" -> btExecutor.execute {
                val ok = try {
                    hidDevice?.unregisterApp() == true
                } catch (e: IllegalStateException) {
                    // unregisterApp throws IllegalStateException when the app
                    // was not registered; that is the requested end state.
                    true
                }
                replyOnMain(result) { ok }
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("args", "connect requires an address", null)
                } else {
                    btExecutor.execute {
                        replyOnMain(result) { connect(address) }
                    }
                }
            }
            "getHosts" -> btExecutor.execute {
                replyOnMain(result) { getHosts() }
            }
            "sendReport" -> {
                val address = call.argument<String>("address")
                val id = call.argument<Int>("id")
                val data = call.argument<ByteArray>("data")
                if (address == null || id == null || data == null) {
                    result.error("args", "sendReport requires address, id and data", null)
                } else {
                    btExecutor.execute {
                        replyOnMain(result) { sendReport(address, id.toByte(), data) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Delivers a method-channel result on the main thread — the Flutter
     * engine requires it, and the Bluetooth work stays on [btExecutor].
     */
    private inline fun replyOnMain(result: Result, compute: () -> Any?) {
        val value = try {
            compute()
        } catch (e: Exception) {
            Log.e(TAG, "method call failed", e)
            mainHandler.post { result.error("hid", e.message ?: "HID call failed", null) }
            return
        }
        mainHandler.post { result.success(value) }
    }

    private fun ensurePermissions(result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            // Below S the legacy BLUETOOTH permission is normal-level and
            // declared in the manifest — nothing to request.
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no-activity", "permission request needs a foreground activity", null)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "a permission request is already in flight", null)
            return
        }
        pendingPermissionResult = result
        currentActivity.requestPermissions(
            arrayOf(android.Manifest.permission.BLUETOOTH_CONNECT),
            PERMISSION_REQUEST_CODE,
        )
    }

    @SuppressLint("MissingPermission")
    private fun register(result: Result) {
        if (!hasConnectPermission()) {
            mainHandler.post { result.error("permission", "BLUETOOTH_CONNECT not granted", null) }
            return
        }
        val localAdapter = adapter
        if (localAdapter == null || !localAdapter.isEnabled) {
            mainHandler.post { result.error("bt-off", "Bluetooth adapter unavailable or disabled", null) }
            return
        }
        if (hidDevice == null && !proxyRequested) {
            proxyRequested = true
            localAdapter.getProfileProxy(context, proxyListener, BluetoothProfile.HID_DEVICE)
        }
        val sdp = BluetoothHidDeviceAppSdpSettings(
            Ds4Descriptors.SDP_NAME,
            Ds4Descriptors.SDP_DESCRIPTION,
            Ds4Descriptors.SDP_PROVIDER,
            Ds4Descriptors.SDP_SUBCLASS,
            Ds4Descriptors.btReportDescriptor,
        )
        val device = hidDevice
        if (device == null) {
            // Proxy not connected yet — onServiceConnected registers.
            pendingRegisterSdp = sdp
            logD("register queued until HID_DEVICE proxy connects")
            mainHandler.post { result.success(true) }
            return
        }
        val queued = try {
            device.registerApp(sdp, null, null, btExecutor, hidCallback)
        } catch (e: Exception) {
            // registerApp can throw on some OEM stacks; fail loudly with the
            // reason instead of leaving Dart waiting forever.
            mainHandler.post { result.error("register", e.message ?: "registerApp failed", null) }
            return
        }
        logD("registerApp sent=$queued")
        mainHandler.post { result.success(queued) }
    }

    private val proxyListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            logD("HID_DEVICE proxy connected")
            val device = proxy as BluetoothHidDevice
            hidDevice = device
            val sdp = pendingRegisterSdp
            pendingRegisterSdp = null
            if (sdp != null) {
                device.registerApp(sdp, null, null, btExecutor, hidCallback)
                logD("queued registerApp sent")
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            logD("HID_DEVICE proxy disconnected")
            hidDevice = null
            proxyRequested = false
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String): Boolean {
        if (!hasConnectPermission()) return false
        val device = hidDevice ?: return false.also { logD("connect failed: not registered") }
        val remote = adapter?.getRemoteDevice(address) ?: return false
        val ok = device.connect(remote)
        logD("connect($address) sent=$ok")
        return ok
    }

    @SuppressLint("MissingPermission")
    private fun getHosts(): List<Map<String, Any?>> {
        if (!hasConnectPermission()) return emptyList()
        val device = hidDevice ?: return emptyList()
        val states = intArrayOf(
            BluetoothProfile.STATE_CONNECTED,
            BluetoothProfile.STATE_CONNECTING,
            BluetoothProfile.STATE_DISCONNECTED,
            BluetoothProfile.STATE_DISCONNECTING,
        )
        return device.getDevicesMatchingConnectionStates(states).map { d ->
            mapOf(
                "address" to d.address,
                "name" to deviceName(d),
                "state" to connectionStateName(device.getConnectionState(d)),
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun sendReport(address: String, id: Byte, data: ByteArray): Boolean {
        if (!hasConnectPermission()) return false
        val device = hidDevice ?: return false.also { logD("sendReport failed: not registered") }
        val remote = adapter?.getRemoteDevice(address) ?: return false
        if (id == Ds4Descriptors.REPORT_ID_INPUT_SMALL) {
            data.copyInto(lastInputReport)
        }
        val ok = device.sendReport(remote, id.toInt(), data)
        if (!ok) logD("sendReport rejected id=$id length=${data.size}")
        return ok
    }

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * Runs [payload] on the Bluetooth thread, then posts its result to the
     * event sink on the main thread. Building the payload on the BT thread
     * keeps device-name lookups (which are binder calls) off the main thread.
     */
    private fun emit(event: String, payload: () -> Map<String, Any?>) {
        btHandler.post {
            val map = HashMap<String, Any?>(payload())
            map["event"] = event
            mainHandler.post { eventSink?.success(map) }
        }
    }

    private fun emitHostRequest(kind: String, type: Byte? = null, id: Byte? = null, length: Int? = null) {
        emit(EVENT_HOST_REQUEST) {
            buildMap<String, Any?> {
                put("kind", kind)
                if (type != null) put("type", type.toInt())
                if (id != null) put("id", id.toInt())
                if (length != null) put("length", length)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun deviceName(device: BluetoothDevice): String? = try {
        device.name
    } catch (e: SecurityException) {
        // Name lookup needs BLUETOOTH_CONNECT; the address is still valid.
        null
    }

    private fun connectionStateName(state: Int): String = when (state) {
        BluetoothProfile.STATE_CONNECTED -> "connected"
        BluetoothProfile.STATE_CONNECTING -> "connecting"
        BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
        BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
        else -> "unknown($state)"
    }

    private fun logD(message: String) {
        // Centralized log point for every HID transition (CONVENTIONS.md:
        // no bare debugPrint; report bytes are never logged).
        Log.d(TAG, message)
    }
}

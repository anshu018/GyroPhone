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
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
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
 * M2 sensor hot loop (ADR-012): a second HandlerThread ([sensorThread])
 * delivers gyro + rotation-vector events and runs [SensorFusion]; it publishes
 * only the fused angle through a volatile field — zero channel crossings, zero
 * allocations per event. [btExecutor] owns everything report-related: the
 * [WheelModel], the [Ds4InputPacker] (single report owner: payload bytes,
 * counter, dedupe, GET_REPORT cache), pedal state, and the ~120 Hz sender tick
 * with latest-state semantics. Fusion parameters marshal to the sensor thread;
 * everything else stays on btExecutor.
 *
 * Permissions: the Dart side calls [ensurePermissions] before anything else.
 * Registration fails loudly on the channel if [BLUETOOTH_CONNECT] is missing;
 * the other methods log the reason and return false/empty rather than throw —
 * a silent failure here is exactly the bug class that costs days on a real
 * device (see docs/specs/M1-pair-as-ds4.md, Pitfalls).
 */
class HidPlugin(private val context: Context, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "HidPlugin"
        private const val METHOD_CHANNEL = "gyrophone/hid"
        private const val EVENT_CHANNEL = "gyrophone/hid_events"
        private const val WHEEL_CHANNEL = "gyrophone/wheel"

        // Event names shared with lib/hid/hid_bridge.dart.
        private const val EVENT_APP_STATUS = "appStatus"
        private const val EVENT_CONNECTION_STATE = "connectionState"
        private const val EVENT_HOST_REQUEST = "hostRequest"
        private const val EVENT_BT_STATE = "btState"
        private const val EVENT_STREAMING = "streaming"

        private const val PERMISSION_REQUEST_CODE = 0x4750 // "GP"
        private const val DISCOVERABLE_REQUEST_CODE = 0x4751 // "GP"+1

        private const val TICK_MS = 8L // sender tick; the 120 Hz cap gates below it
        private const val MIN_SEND_INTERVAL_NS = 8_333_333L // 120 Hz
        private const val UI_EMIT_INTERVAL_NS = 16_666_667L // ≤60 Hz wheel stream
        private const val LATENCY_RING_SIZE = 128
        private const val AUTO_ZERO_HOLD_NS = 1_200_000_000L // held still 1.2 s → capture grip
        private const val AUTO_ZERO_TOLERANCE_DEG = 1.5f
        private const val PACKED_EMPTY = Long.MIN_VALUE
        private const val HEARTBEAT_NS = 5_000_000_000L // device-debug heartbeat; temporary
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val btThread = HandlerThread("gyrophone-hid").apply { start() }
    private val btHandler = Handler(btThread.looper)
    private val btExecutor = Executor { task -> btHandler.post(task) }
    private val sensorThread = HandlerThread("gyrophone-sensors").apply { start() }
    private val sensorHandler = Handler(sensorThread.looper)

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val wheelChannel = EventChannel(messenger, WHEEL_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var wheelSink: EventChannel.EventSink? = null

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var hidDevice: BluetoothHidDevice? = null
    private var proxyRequested = false
    private var pendingRegisterSdp: BluetoothHidDeviceAppSdpSettings? = null

    // --- M2 hot loop (ADR-012): fusion on [sensorThread], reports on [btExecutor] ---
    private val fusion = SensorFusion()
    private val wheelModel = WheelModel()
    private val packer = Ds4InputPacker()

    // Sensor-thread publication. One packed volatile word so the tick can
    // never read the angle of one event with the arrival time of a newer one
    // (device finding 2026-11-11: separate volatiles produced negative
    // latency). High 32 bits: angle in centidegrees. Low 32: arrival
    // SystemClock time; both ends subtract in 32-bit wrap, correct for any
    // true delta < 2.1 s.
    @Volatile private var latestSampleBits = PACKED_EMPTY
    @Volatile private var sensorEventCount = 0L

    // btExecutor-owned hot-loop state.
    private var armed = false // setStreaming from Dart
    private var linked = false // host connection state, from the HID callback
    private var hostAddress: String? = null
    private var pedalThrottle = 0
    private var pedalBrake = 0
    private var lastSendNanos = 0L
    private var streamingNotified = false
    private val latencyRing = FloatArray(LATENCY_RING_SIZE)
    private val latencyScratch = FloatArray(LATENCY_RING_SIZE)
    private var latencyCount = 0
    private var latencyIndex = 0
    private var lastUiEmitNanos = 0L
    private var lastRateSampleNanos = 0L
    private var lastRateSampleCount = 0L
    private var lastHeartbeatNanos = 0L
    private var sendsSinceReconnect = 0
    private val tickTask = object : Runnable {
        override fun run() {
            tick()
            btHandler.postDelayed(this, TICK_MS)
        }
    }

    // Auto re-zero (launch grip calibration): the first time the phone has
    // been held nearly still for a moment after the fusion is ready, that
    // grip becomes "straight" — the user must not need the RE-ZERO button
    // every session (device finding 2026-11-11: reference used to stay at
    // the launch pose, so a landscape grip read ~60°). Once per process;
    // grip changes mid-session are what the RE-ZERO button is for.
    private var autoZeroed = false
    private var autoZeroPendingAngle = 0f
    private var autoZeroPendingSinceNs = 0L

    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val t0 = SystemClock.elapsedRealtimeNanos()
            when (event.sensor.type) {
                Sensor.TYPE_GYROSCOPE -> if (event.values.size >= 3) {
                    fusion.onGyro(event.values[0], event.values[1], event.values[2], event.timestamp)
                }
                Sensor.TYPE_ROTATION_VECTOR -> if (event.values.size >= 4) {
                    fusion.onRotationVector(event.values[0], event.values[1], event.values[2], event.values[3])
                }
                else -> return
            }
            val angle = fusion.wheelAngleDeg()
            latestSampleBits = ((angle * 100).toLong() shl 32) or (t0 and 0xFFFFFFFFL)
            sensorEventCount++
            maybeAutoZero(angle, t0)
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    /** Unpacks the latest sample; null before the first sensor event. */
    private fun latestSample(): Pair<Float, Long>? {
        val bits = latestSampleBits
        if (bits == PACKED_EMPTY) return null
        val angle = (bits shr 32).toInt() / 100f
        val arrival = bits and 0xFFFFFFFFL
        return angle to arrival
    }

    /** Captures the reference once the phone has held still in a grip. */
    private fun maybeAutoZero(angle: Float, nowNs: Long) {
        if (autoZeroed || !fusion.isReady()) return
        if (autoZeroPendingSinceNs == 0L) {
            autoZeroPendingAngle = angle
            autoZeroPendingSinceNs = nowNs
            return
        }
        if (nowNs - autoZeroPendingSinceNs < AUTO_ZERO_HOLD_NS) return
        if (kotlin.math.abs(angle - autoZeroPendingAngle) <= AUTO_ZERO_TOLERANCE_DEG) {
            fusion.captureReference()
            autoZeroed = true
            // Re-publish with the fresh (now zero) angle so the next tick
            // sends the new straight position immediately.
            val t0 = SystemClock.elapsedRealtimeNanos()
            latestSampleBits = ((fusion.wheelAngleDeg() * 100).toLong() shl 32) or (t0 and 0xFFFFFFFFL)
            logD("auto re-zero captured the current grip")
        } else {
            // Still being moved — restart the stillness window.
            autoZeroPendingAngle = angle
            autoZeroPendingSinceNs = nowNs
        }
    }

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
            // Runs on btExecutor (the callback executor): hot-loop gates update
            // in place. On disconnect the streaming notification re-arms so a
            // reconnect promotes to streaming again.
            linked = state == BluetoothProfile.STATE_CONNECTED
            hostAddress = if (linked) device.address else null
            if (!linked) streamingNotified = false
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
            try {
                if (type == BluetoothHidDevice.REPORT_TYPE_INPUT && id == Ds4Descriptors.REPORT_ID_INPUT_SMALL) {
                    val current = packer.currentPayload()
                    val reply = ByteArray(maxOf(bufferSize, current.size))
                    current.copyInto(reply)
                    val replied = hidDevice?.replyReport(device, type, id, reply) ?: false
                    if (!replied) logD("replyReport rejected (input 0x01)")
                } else if (type == BluetoothHidDevice.REPORT_TYPE_FEATURE && id == Ds4Descriptors.FEATURE_ID_CALIBRATION) {
                    // M1 replies with zeros; real calibration values are Step 2
                    // (docs/specs/M1-pair-as-ds4.md R6). Windows never asks; a
                    // Steam DS4 path would — the log entry is the evidence.
                    val reply = ByteArray(maxOf(bufferSize, Ds4Descriptors.FEATURE_CALIBRATION_SIZE))
                    val replied = hidDevice?.replyReport(device, type, id, reply) ?: false
                    if (!replied) logD("replyReport rejected (feature 0x02)")
                } else {
                    logD("onGetReport unsupported: type=$type id=$id")
                    hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_UNSUPPORTED_REQ)
                }
            } catch (e: Exception) {
                // SecurityException (permission revoked mid-session) or an
                // IllegalStateException from a stale proxy must not take the
                // process down from a binder callback.
                Log.e(TAG, "onGetReport handling failed", e)
            }
            emitHostRequest("getReport", type = type, id = id)
        }

        override fun onSetReport(device: BluetoothDevice, type: Byte, id: Byte, data: ByteArray) {
            // Output reports arrive here (control channel) or via
            // onInterruptData (interrupt channel). M1 only records them; real
            // consumption is Step 2/5.
            logD("onSetReport type=$type id=$id length=${data.size}")
            try {
                hidDevice?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS)
            } catch (e: Exception) {
                Log.e(TAG, "onSetReport handshake failed", e)
            }
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
        wheelChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                wheelSink = events
            }

            override fun onCancel(arguments: Any?) {
                wheelSink = null
            }
        })
        ContextCompat.registerReceiver(
            context,
            btStateReceiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
            // EXPORTED, not NOT_EXPORTED: ACTION_STATE_CHANGED can be delivered
            // from the Bluetooth mainline-module process, and NOT_EXPORTED
            // silently drops it on some Android 14+ builds (Google issue
            // 302209811). The action is a protected broadcast — nothing can
            // spoof it — so EXPORTED is safe here. Delivery is verified on
            // both R9 devices; onAppStatusChanged stays the backup truth.
            ContextCompat.RECEIVER_EXPORTED,
        )
        startSensors()
        btHandler.post(tickTask)
    }

    /** Registers the IMU listeners at the fastest rate the hardware offers.
     *  HIGH_SAMPLING_RATE_SENSORS is declared (manifest) — without it a
     *  target-31+ app is capped at 200 Hz and requests above that throw
     *  (RESEARCH.md, platform constraints). Runs for the plugin's lifetime;
     *  the armed/linked gates keep the loop silent when it must not send. */
    @SuppressLint("MissingPermission")
    private fun startSensors() {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val gyro = manager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        val rotation = manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        if (gyro == null || rotation == null) {
            Log.e(TAG, "sensor start failed: gyro=${gyro != null} rotationVector=${rotation != null}")
            return
        }
        val registered = manager.registerListener(sensorListener, gyro, SensorManager.SENSOR_DELAY_FASTEST, sensorHandler) &&
            manager.registerListener(sensorListener, rotation, SensorManager.SENSOR_DELAY_FASTEST, sensorHandler)
        logD("sensors registered=$registered gyro=${gyro.name} rotationVector=${rotation.name}")
    }

    private fun stopSensors() {
        (context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager)
            ?.unregisterListener(sensorListener)
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun dispose() {
        // A permission request in flight must not leave Dart hanging forever.
        pendingPermissionResult?.error("disposed", "plugin torn down during permission request", null)
        pendingPermissionResult = null
        discoverableResult?.error("disposed", "plugin torn down during discoverable request", null)
        discoverableResult = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        wheelChannel.setStreamHandler(null)
        btHandler.removeCallbacks(tickTask)
        stopSensors()
        sensorThread.quitSafely()
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
            "requestDiscoverable" -> requestDiscoverable(result)
            "setWheelParams" -> setWheelParams(call, result)
            "reZero" -> sensorHandler.post {
                fusion.captureReference()
                replyOnMain(result) { true }
            }
            "setPedals" -> setPedals(call, result)
            "setStreaming" -> setStreaming(call, result)
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

    /**
     * Makes the phone discoverable for 5 minutes via the system consent
     * dialog — shown OVER our activity, so the registered app stays in the
     * foreground while the PC pairs. This is functionally required on this
     * platform: with the app backgrounded (user in Bluetooth settings), the
     * stack refuses to complete the HID connection and Windows fails driver
     * install (docs/specs/M1-pair-as-ds4.md, Pitfalls — observed on-device).
     */
    private fun requestDiscoverable(result: Result) {
        val currentActivity = activity
        if (currentActivity == null) {
            result.error("no-activity", "discoverable request needs a foreground activity", null)
            return
        }
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
            putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
        }
        discoverableResult = result
        currentActivity.startActivityForResult(intent, DISCOVERABLE_REQUEST_CODE)
    }

    private var discoverableResult: Result? = null

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        if (requestCode != DISCOVERABLE_REQUEST_CODE) return
        val result = discoverableResult
        discoverableResult = null
        val allowed = resultCode != 0 // duration in seconds, 0/canceled = denied
        logD("discoverable request allowed=$allowed duration=$resultCode")
        result?.success(allowed)
        if (allowed) {
            emit(EVENT_BT_STATE) { mapOf("state" to "discoverable") }
        }
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
            val requested = localAdapter.getProfileProxy(context, proxyListener, BluetoothProfile.HID_DEVICE)
            if (!requested) {
                // The profile is absent on some OEM builds — fail loudly so
                // Dart shows an error instead of waiting forever.
                proxyRequested = false
                mainHandler.post {
                    result.error("no-profile", "HID device profile unavailable on this device", null)
                }
                return
            }
        }
        val sdp = BluetoothHidDeviceAppSdpSettings(
            Ds4Descriptors.SDP_NAME,
            Ds4Descriptors.SDP_DESCRIPTION,
            Ds4Descriptors.SDP_PROVIDER,
            Ds4Descriptors.SDP_SUBCLASS,
            Ds4Descriptors.activeReportDescriptor,
        )
        val device = hidDevice
        if (device == null) {
            // Proxy not connected yet — onServiceConnected registers.
            pendingRegisterSdp = sdp
            logD("register queued until HID_DEVICE proxy connects")
            mainHandler.post { result.success("queued") }
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
        // "sent" / "queued" describes what happened; registration truth is
        // still onAppStatusChanged (docs/specs/M1-pair-as-ds4.md R2).
        mainHandler.post { result.success(if (queued) "sent" else "rejected") }
    }

    private val proxyListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            logD("HID_DEVICE proxy connected")
            // Registration happens on the Bluetooth thread with the same
            // guards as an explicit register call — never on the binder
            // thread, and never without the permission re-checked.
            btHandler.post {
                val device = proxy as BluetoothHidDevice
                hidDevice = device
                val sdp = pendingRegisterSdp
                pendingRegisterSdp = null
                if (sdp == null) return@post
                if (!hasConnectPermission()) {
                    logD("queued registerApp dropped: BLUETOOTH_CONNECT revoked")
                    return@post
                }
                val queued = try {
                    device.registerApp(sdp, null, null, btExecutor, hidCallback)
                } catch (e: Exception) {
                    Log.e(TAG, "queued registerApp failed", e)
                    false
                }
                logD("queued registerApp sent=$queued")
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
        if (!hasConnectPermission()) {
            logD("connect($address) failed: BLUETOOTH_CONNECT missing")
            return false
        }
        val device = hidDevice ?: return false.also { logD("connect($address) failed: not registered") }
        val localAdapter = adapter ?: return false.also { logD("connect($address) failed: adapter unavailable") }
        val remote = remoteDevice(localAdapter, address) ?: return false.also {
            logD("connect($address) failed: malformed address")
        }
        val ok = device.connect(remote)
        logD("connect($address) sent=$ok")
        return ok
    }

    @SuppressLint("MissingPermission")
    private fun getHosts(): List<Map<String, Any?>> {
        if (!hasConnectPermission()) {
            logD("getHosts failed: BLUETOOTH_CONNECT missing")
            return emptyList()
        }
        val device = hidDevice
        if (device == null) {
            logD("getHosts failed: not registered")
            return emptyList()
        }
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

    private fun setWheelParams(call: MethodCall, result: Result) {
        val range = call.argument<Double>("range")
        val deadzone = call.argument<Double>("deadzone")
        val sensitivity = call.argument<Double>("sensitivity")
        val curve = call.argument<String>("curve")
        val axisMode = call.argument<String>("axisMode")
        if (range == null || deadzone == null || sensitivity == null || curve == null || axisMode == null) {
            result.error("args", "setWheelParams requires range, deadzone, sensitivity, curve, axisMode", null)
            return
        }
        btExecutor.execute {
            // Params are clamped by WheelModel's setters; unknown enum strings
            // fall back to the safe defaults rather than failing the channel.
            wheelModel.rangeDeg = range.toFloat()
            wheelModel.deadzoneDeg = deadzone.toFloat()
            wheelModel.sensitivity = sensitivity.toFloat()
            wheelModel.curve = when (curve) {
                "soft" -> WheelModel.Curve.SOFT
                "sharp" -> WheelModel.Curve.SHARP
                else -> WheelModel.Curve.LINEAR
            }
            val mode = when (axisMode) {
                "flat" -> SensorFusion.AxisMode.FLAT
                "cradle" -> SensorFusion.AxisMode.CRADLE
                else -> SensorFusion.AxisMode.AUTO
            }
            // Fusion state is sensor-thread confined — marshal the axis mode.
            sensorHandler.post { fusion.axisMode = mode }
            replyOnMain(result) { true }
        }
    }

    private fun setPedals(call: MethodCall, result: Result) {
        val throttle = call.argument<Int>("throttle")
        val brake = call.argument<Int>("brake")
        if (throttle == null || brake == null) {
            result.error("args", "setPedals requires throttle and brake", null)
            return
        }
        btExecutor.execute {
            pedalThrottle = throttle.coerceIn(0, 255)
            pedalBrake = brake.coerceIn(0, 255)
            replyOnMain(result) { true }
        }
    }

    private fun setStreaming(call: MethodCall, result: Result) {
        val enabled = call.argument<Boolean>("enabled")
        if (enabled == null) {
            result.error("args", "setStreaming requires enabled", null)
            return
        }
        btExecutor.execute {
            val wasArmed = armed
            armed = enabled
            if (!enabled && wasArmed && linked) {
                // Focus loss / explicit disarm: the host must never hold a held
                // wheel angle or a pressed pedal (M2 spec R1) — send neutral.
                if (packer.pack(WheelModel.CENTER, 0, 0)) {
                    val address = hostAddress
                    if (address != null) {
                        sendReport(address, Ds4Descriptors.REPORT_ID_INPUT_SMALL, packer.currentPayload())
                    }
                }
            }
            replyOnMain(result) { true }
        }
    }

    /**
     * The sender tick (btExecutor): applies the wheel model to the freshest
     * fused angle, packs, and sends when the wire changes — capped at 120 Hz
     * with latest-state semantics (never batched, never stale). Also paces the
     * ≤60 Hz wheel UI stream and the sensor-rate/latency sampling.
     */
    private fun tick() {
        val now = SystemClock.elapsedRealtimeNanos()
        emitWheelStateMaybe(now)
        if (now - lastHeartbeatNanos >= HEARTBEAT_NS) {
            lastHeartbeatNanos = now
            logD("tick armed=$armed linked=$linked angle=${latestSample()?.first} pedals=$pedalThrottle/$pedalBrake sends=$sendsSinceReconnect")
        }
        if (!armed || !linked) return
        if (now - lastSendNanos < MIN_SEND_INTERVAL_NS) return
        val sample = latestSample() ?: return
        val steering = wheelModel.apply(sample.first)
        if (!packer.pack(steering, pedalThrottle, pedalBrake)) return
        val address = hostAddress ?: return
        val ok = sendReport(address, Ds4Descriptors.REPORT_ID_INPUT_SMALL, packer.currentPayload())
        if (ok) {
            lastSendNanos = now
            sendsSinceReconnect++
            // 32-bit-wrap subtraction; skip samples older than the 2.1 s wrap.
            val deltaNs = (now - sample.second) and 0xFFFFFFFFL
            if (deltaNs <= Int.MAX_VALUE) recordLatency(deltaNs / 1e6f)
            if (!streamingNotified) {
                streamingNotified = true
                emit(EVENT_STREAMING) { mapOf("started" to true) }
            }
        } else {
            // A rejected send must not poison dedupe — the host may not hold
            // the report, so the next identical state re-sends (M1 semantics).
            packer.invalidateLastSent()
        }
    }

    private fun recordLatency(ms: Float) {
        latencyRing[latencyIndex] = ms
        latencyIndex = (latencyIndex + 1) % LATENCY_RING_SIZE
        if (latencyCount < LATENCY_RING_SIZE) latencyCount++
    }

    private fun emitWheelStateMaybe(now: Long) {
        if (now - lastUiEmitNanos < UI_EMIT_INTERVAL_NS) return
        val firstSample = lastRateSampleNanos == 0L
        val hz = if (firstSample) {
            0f
        } else {
            val seconds = (now - lastRateSampleNanos) / 1e9f
            if (seconds > 0f) ((sensorEventCount - lastRateSampleCount) / seconds) else 0f
        }
        lastUiEmitNanos = now
        lastRateSampleNanos = now
        lastRateSampleCount = sensorEventCount
        val stats = latencyStats()
        val angle = latestSample()?.first ?: 0f
        val samples = latencyCount
        mainHandler.post {
            wheelSink?.success(
                mapOf(
                    "angle" to angle,
                    "avg" to stats?.first,
                    "p95" to stats?.second,
                    "n" to samples,
                    "sensorHz" to hz,
                )
            )
        }
    }

    /** (avg, p95) over the latency ring; null until the first send. */
    private fun latencyStats(): Pair<Float, Float>? {
        if (latencyCount == 0) return null
        System.arraycopy(latencyRing, 0, latencyScratch, 0, latencyCount)
        java.util.Arrays.sort(latencyScratch, 0, latencyCount)
        var sum = 0f
        for (i in 0 until latencyCount) sum += latencyScratch[i]
        val p95Index = ((latencyCount * 95) / 100).coerceIn(0, latencyCount - 1)
        return sum / latencyCount to latencyScratch[p95Index]
    }

    @SuppressLint("MissingPermission")
    private fun sendReport(address: String, id: Byte, data: ByteArray): Boolean {
        if (!hasConnectPermission()) {
            logD("sendReport failed: BLUETOOTH_CONNECT missing")
            return false
        }
        val device = hidDevice ?: return false.also { logD("sendReport failed: not registered") }
        val localAdapter = adapter ?: return false.also { logD("sendReport failed: adapter unavailable") }
        val remote = remoteDevice(localAdapter, address) ?: return false.also {
            logD("sendReport failed: malformed address")
        }
        val ok = try {
            device.sendReport(remote, id.toInt(), data)
        } catch (e: Exception) {
            Log.e(TAG, "sendReport failed", e)
            false
        }
        if (!ok) logD("sendReport rejected id=$id length=${data.size}")
        return ok
    }

    /** getRemoteDevice throws IllegalArgumentException on a malformed
     *  address; the address comes from callbacks and callers, so guard it. */
    @SuppressLint("MissingPermission")
    private fun remoteDevice(adapter: BluetoothAdapter, address: String): BluetoothDevice? =
        try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            null
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
        // no bare debugPrint; report bytes are never logged). Logged at INFO:
        // this OxygenOS 16 build drops app-level DEBUG lines from logcat
        // entirely (observed 2026-11-11 — M1 never noticed because its
        // debugging leaned on Bluetooth-stack logs). INFO always passes.
        Log.i(TAG, message)
    }
}

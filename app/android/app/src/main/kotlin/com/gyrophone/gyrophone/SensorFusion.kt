package com.gyrophone.gyrophone

/**
 * Fuses the gyroscope and the rotation vector into a wheel angle.
 *
 * Algorithm: complementary fusion. The orientation estimate is integrated from
 * gyro events (low latency, fast path) and nudged toward each rotation-vector
 * event with a small fixed gain (drift correction). The wheel angle is the
 * rotation component of the relative orientation (re-zero reference ⊗ current)
 * about the wheel axis, positive for clockwise (steer right).
 *
 * Grip models the spec's axis choice (M2 spec R2): a near-flat grip steers by
 * rotating about world up (yaw); a cradled grip steers by rotating about the
 * horizontal screen normal. AUTO switches between them with a hysteresis band;
 * a manual override pins one mode.
 *
 * Android facts this class relies on (verified 2026-11-11, see RESEARCH.md):
 * rotation-vector values are the quaternion (x, y, z, w) of device→world with
 * world +Z pointing up, and sensor coordinates follow the device's natural
 * orientation — never the app's landscape lock. All math here therefore works
 * in the sensor frame.
 *
 * Single-thread confined (the sensor HandlerThread): fields are plain vars.
 * Re-zero and configuration are marshaled to that thread by the caller.
 * No allocations in the event paths — scratch arrays are reused (M2 spec R1).
 */
class SensorFusion {

    enum class AxisMode { AUTO, FLAT, CRADLE }

    /** Fraction of the remaining rotation-vector error corrected per event. */
    private val rvGain = 0.05f

    // Orientation estimate, device→world, (w, x, y, z).
    private var qw = 1f
    private var qx = 0f
    private var qy = 0f
    private var qz = 0f

    // Re-zero reference orientation, device→world.
    private var refW = 1f
    private var refX = 0f
    private var refY = 0f
    private var refZ = 0f

    private var lastGyroTimestampNs = 0L
    private var hasEstimate = false

    var axisMode = AxisMode.AUTO

    // Hysteresis state for AUTO: |screen-normal · world-up| above ENTER_FLAT
    // switches to flat, below EXIT_FLAT switches to cradle (band ≈ 40°–50°).
    private var flatModeActive = true

    private val scratchA = FloatArray(4)
    private val scratchB = FloatArray(4)
    private val scratchV = FloatArray(3)

    /** Integrates one gyroscope event (rad/s, sensor frame) into the estimate. */
    fun onGyro(wx: Float, wy: Float, wz: Float, timestampNs: Long) {
        val last = lastGyroTimestampNs
        lastGyroTimestampNs = timestampNs
        if (last == 0L) return
        val dt = (timestampNs - last) * 1e-9f
        if (dt <= 0f || dt > 0.5f) return // stale pair (resume gap); skip, RV re-corrects
        val rate = kotlin.math.sqrt(wx * wx + wy * wy + wz * wz) // rad/s
        val theta = rate * dt
        if (theta < 1e-9f) return
        val half = theta * 0.5f
        // δv = ω̂·sin(θ/2) = ω·sin(θ/2)/|ω| — the scale divides by the RATE,
        // not by the angle (dividing by θ overshot every step ~1/dt×; the
        // golden-scenario tests caught exactly this).
        val s = kotlin.math.sin(half) / rate
        // δq = (cos(θ/2), ω̂·sin(θ/2)); q ← q ⊗ δq (sensor-frame rates right-multiply).
        val dw = kotlin.math.cos(half)
        val dx = wx * s
        val dy = wy * s
        val dz = wz * s
        val a = scratchA
        a[0] = qw; a[1] = qx; a[2] = qy; a[3] = qz
        qw = a[0] * dw - a[1] * dx - a[2] * dy - a[3] * dz
        qx = a[0] * dx + a[1] * dw + a[2] * dz - a[3] * dy
        qy = a[0] * dy - a[1] * dz + a[2] * dw + a[3] * dx
        qz = a[0] * dz + a[1] * dy - a[2] * dx + a[3] * dw
        normalizeEstimate()
    }

    /** Corrects the estimate toward one rotation-vector event (x, y, z, w). */
    fun onRotationVector(x: Float, y: Float, z: Float, w: Float) {
        val len = kotlin.math.sqrt(x * x + y * y + z * z + w * w)
        if (len < 1e-9f) return
        var mx = x / len
        var my = y / len
        var mz = z / len
        var mw = w / len
        if (!hasEstimate) {
            qw = mw; qx = mx; qy = my; qz = mz
            hasEstimate = true
            return
        }
        // Antipodal equivalence: q and −q are the same rotation; keep the blend short.
        if (qw * mw + qx * mx + qy * my + qz * mz < 0f) {
            mx = -mx; my = -my; mz = -mz; mw = -mw
        }
        qw += rvGain * (mw - qw)
        qx += rvGain * (mx - qx)
        qy += rvGain * (my - qy)
        qz += rvGain * (mz - qz)
        normalizeEstimate()
    }

    /** Re-zero: the current grip becomes "straight". Marshaled to the sensor thread. */
    fun captureReference() {
        refW = qw; refX = qx; refY = qy; refZ = qz
    }

    /** True once both a rotation vector and the reference exist. */
    fun isReady(): Boolean = hasEstimate

    /** True when the grip model currently classifies the hold as "flat" (yaw steering). */
    internal fun isFlatGrip(): Boolean {
        applyHysteresis(kotlin.math.abs(rotateWorldZ(qw, qx, qy, qz, 0f, 0f, 1f)))
        return flatModeActive
    }

    private fun applyHysteresis(upComponent: Float) {
        if (upComponent > ENTER_FLAT) flatModeActive = true
        else if (upComponent < EXIT_FLAT) flatModeActive = false
    }

    /**
     * The fused wheel angle in degrees, positive for clockwise (steer right),
     * relative to the re-zero reference. Returns 0 until an estimate exists.
     */
    fun wheelAngleDeg(): Float {
        if (!hasEstimate) return 0f
        // Wheel axis in world frame, chosen by mode (with hysteresis in AUTO).
        val nwx = rotateWorldX(qw, qx, qy, qz, 0f, 0f, 1f)
        val nwy = rotateWorldY(qw, qx, qy, qz, 0f, 0f, 1f)
        val nwz = rotateWorldZ(qw, qx, qy, qz, 0f, 0f, 1f)
        applyHysteresis(kotlin.math.abs(nwz))
        val flat = when (axisMode) {
            AxisMode.AUTO -> flatModeActive
            AxisMode.FLAT -> true
            AxisMode.CRADLE -> false
        }
        var axw: Float
        var ayw: Float
        var azw: Float
        if (flat) {
            axw = 0f; ayw = 0f; azw = 1f // world up (yaw)
        } else {
            axw = nwx; ayw = nwy; azw = 0f // horizontal screen normal
            val h = kotlin.math.sqrt(axw * axw + ayw * ayw)
            if (h < 1e-4f) { axw = 1f; ayw = 0f } // degenerate tilt guard
            else { axw /= h; ayw /= h }
        }
        // Relative rotation and the axis in the reference device frame.
        val rel = scratchA
        rel[0] = refW * qw + refX * qx + refY * qy + refZ * qz
        rel[1] = refW * qx - refX * qw - refY * qz + refZ * qy
        rel[2] = refW * qy + refX * qz - refY * qw - refZ * qx
        rel[3] = refW * qz - refX * qy + refY * qx - refZ * qw
        val ar = scratchB
        ar[0] = 0f
        ar[1] = rotateWorldX(refW, -refX, -refY, -refZ, axw, ayw, azw)
        ar[2] = rotateWorldY(refW, -refX, -refY, -refZ, axw, ayw, azw)
        ar[3] = rotateWorldZ(refW, -refX, -refY, -refZ, axw, ayw, azw)
        // Rotation component about the wheel axis; negated so clockwise (steer
        // right, viewed from the axis tip) is positive.
        val thetaRad = -2f * kotlin.math.atan2(
            rel[1] * ar[1] + rel[2] * ar[2] + rel[3] * ar[3],
            rel[0]
        )
        return thetaRad * RAD_TO_DEG
    }

    private fun normalizeEstimate() {
        val n = kotlin.math.sqrt(qw * qw + qx * qx + qy * qy + qz * qz)
        if (n < 1e-9f) return
        qw /= n; qx /= n; qy /= n; qz /= n
    }

    /** v rotated into the world by q (device→world): used on device-frame axes. */
    private fun rotateWorldX(w: Float, x: Float, y: Float, z: Float, vx: Float, vy: Float, vz: Float): Float {
        // t = 2 (q_v × v); v' = v + w·t + q_v × t
        val tx = 2f * (y * vz - z * vy)
        val ty = 2f * (z * vx - x * vz)
        val tz = 2f * (x * vy - y * vx)
        return vx + w * tx + (y * tz - z * ty)
    }

    private fun rotateWorldY(w: Float, x: Float, y: Float, z: Float, vx: Float, vy: Float, vz: Float): Float {
        val tx = 2f * (y * vz - z * vy)
        val ty = 2f * (z * vx - x * vz)
        val tz = 2f * (x * vy - y * vx)
        return vy + w * ty + (z * tx - x * tz)
    }

    private fun rotateWorldZ(w: Float, x: Float, y: Float, z: Float, vx: Float, vy: Float, vz: Float): Float {
        val tx = 2f * (y * vz - z * vy)
        val ty = 2f * (z * vx - x * vz)
        val tz = 2f * (x * vy - y * vx)
        return vz + w * tz + (x * ty - y * tx)
    }

    companion object {
        const val ENTER_FLAT = 0.77f // |n·up| above this ≈ tilt < 40° → flat grip
        const val EXIT_FLAT = 0.64f  // |n·up| below this ≈ tilt > 50° → cradle grip
        private const val RAD_TO_DEG = 57.29577951308232f
    }
}

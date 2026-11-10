package com.gyrophone.gyrophone

import kotlin.math.pow

/**
 * Transforms a fused wheel angle (degrees) into the report-0x01 steering byte.
 *
 * Pipeline order is the spec's (M2 spec R3): deadzone in physical degrees →
 * sensitivity → response curve (shape applied to the normalized value so the
 * ±range/2 endpoints are preserved) → clamp → byte mapping
 * 128 + round(127 · v). Positive input = steer right.
 *
 * Pure math, no allocations, confined to btExecutor (plain vars for params).
 * Exhaustively unit-tested — silent mapping bugs are steering feel bugs.
 */
class WheelModel {

    enum class Curve { LINEAR, SOFT, SHARP }

    var rangeDeg = DEFAULT_RANGE_DEG
        set(value) { field = value.coerceIn(MIN_RANGE_DEG, MAX_RANGE_DEG) }

    var deadzoneDeg = DEFAULT_DEADZONE_DEG
        set(value) { field = value.coerceIn(0f, MAX_DEADZONE_DEG) }

    var sensitivity = DEFAULT_SENSITIVITY
        set(value) { field = value.coerceIn(MIN_SENSITIVITY, MAX_SENSITIVITY) }

    var curve = Curve.LINEAR

    /** Maps an angle in degrees to the unsigned steering byte (center 128). */
    fun apply(angleDeg: Float): Int {
        var a = angleDeg
        val dz = deadzoneDeg
        if (a > -dz && a < dz) {
            return CENTER
        }
        a = if (a > 0f) a - dz else a + dz // sign-preserving rescale outside the band
        a *= sensitivity
        // Normalize against the EFFECTIVE half-range (what remains after the
        // deadzone) so ±range/2 physical still reaches full lock.
        val effectiveHalf = rangeDeg * 0.5f - dz
        var n = a / (if (effectiveHalf > 1e-3f) effectiveHalf else 1f)
        if (n > 1f) n = 1f
        if (n < -1f) n = -1f
        val gamma = when (curve) {
            Curve.LINEAR -> 1.0f
            Curve.SOFT -> 1.5f // gentler center, more precision where hands rest
            Curve.SHARP -> 0.6f // aggressive center
        }
        val shaped = if (n >= 0f) n.pow(gamma) else -(-n).pow(gamma)
        return CENTER + kotlin.math.round(shaped * 127f).toInt()
    }

    companion object {
        const val MIN_RANGE_DEG = 90f
        const val MAX_RANGE_DEG = 900f
        const val DEFAULT_RANGE_DEG = 900f
        const val DEFAULT_DEADZONE_DEG = 1.5f
        const val MAX_DEADZONE_DEG = 15f
        const val DEFAULT_SENSITIVITY = 1.0f
        const val MIN_SENSITIVITY = 0.2f
        const val MAX_SENSITIVITY = 3.0f
        const val CENTER = 128
    }
}

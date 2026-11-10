package com.gyrophone.gyrophone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Fusion scenarios are built with this file's own tiny quaternion helper —
 * deliberately independent from the production math so the tests cross-check
 * it. Conventions match the Android rotation vector: (x, y, z, w),
 * device→world, world +Z up.
 */
class SensorFusionTest {

    // --- independent quaternion helpers ---

    private fun axisAngle(ax: Float, ay: Float, az: Float, deg: Double): FloatArray {
        val len = sqrt(ax * ax + ay * ay + az * az)
        val half = Math.toRadians(deg) / 2
        val s = sin(half).toFloat() / len
        return floatArrayOf(ax * s, ay * s, az * s, cos(half).toFloat())
    }

    private fun feedRv(fusion: SensorFusion, q: FloatArray) {
        fusion.onRotationVector(q[0], q[1], q[2], q[3])
    }

    /** Feeds a constant body-frame rate (rad/s) for `seconds` in 10 ms steps.
     *  Feeds steps+1 events: the first only starts the clock (no dt yet), so
     *  exactly `seconds` worth of steps is integrated. */
    private fun feedGyro(fusion: SensorFusion, wx: Float, wy: Float, wz: Float, seconds: Double) {
        val stepNs = 10_000_000L
        var t = 0L
        val steps = (seconds * 100).toInt()
        repeat(steps + 1) {
            t += stepNs
            fusion.onGyro(wx, wy, wz, t)
        }
    }

    // --- scenarios ---

    @Test
    fun `flat grip - clockwise yaw gives positive degrees`() {
        val fusion = SensorFusion() // identity reference = device flat, screen up
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        fusion.captureReference()
        assertEquals(0f, fusion.wheelAngleDeg(), 0.001f)
        // Clockwise viewed from above = negative right-hand rate about world +Z.
        feedGyro(fusion, 0f, 0f, -Math.PI.toFloat() / 2, seconds = 1.0)
        assertEquals(90f, fusion.wheelAngleDeg(), 0.5f)
    }

    @Test
    fun `cradle grip - clockwise turn gives positive degrees`() {
        val fusion = SensorFusion()
        feedRv(fusion, axisAngle(1f, 0f, 0f, 90.0)) // top up, screen facing the user
        fusion.captureReference()
        assertFalse(fusion.isFlatGrip()) // 90° tilt from flat → cradle
        // Clockwise as the user sees it = negative right-hand rate about the screen normal.
        feedGyro(fusion, 0f, 0f, -Math.PI.toFloat() / 2, seconds = 1.0)
        assertEquals(90f, fusion.wheelAngleDeg(), 0.5f)
    }

    @Test
    fun `flat grip - counterclockwise gives negative degrees`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        fusion.captureReference()
        feedGyro(fusion, 0f, 0f, Math.PI.toFloat() / 2, seconds = 0.5)
        assertEquals(-45f, fusion.wheelAngleDeg(), 0.5f)
    }

    @Test
    fun `gyro bias drifts the angle and the rotation vector pulls it back`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        fusion.captureReference()
        // 90° clockwise of true rotation; the +0.01 rad/s bias is counterclockwise,
        // so the integrated angle lands slightly short of 90.
        feedGyro(fusion, 0f, 0f, -Math.PI.toFloat() / 2 + 0.01f, seconds = 1.0)
        assertEquals(90f, fusion.wheelAngleDeg(), 1.0f)
        // Pure bias for 60 s: counterclockwise drift ≈ −34.4°.
        feedGyro(fusion, 0f, 0f, 0.01f, seconds = 60.0)
        assertTrue(
            "bias should have drifted the angle well below 90, was ${fusion.wheelAngleDeg()}",
            fusion.wheelAngleDeg() < 60f
        )
        // The truth: still the 90° pose. Feeding it must pull the estimate back.
        val truth = axisAngle(0f, 0f, 1f, -90.0)
        repeat(300) { feedRv(fusion, truth) }
        assertEquals(90f, fusion.wheelAngleDeg(), 0.1f)
    }

    @Test
    fun `antipodal rotation vector does not wobble the estimate`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        fusion.captureReference()
        feedGyro(fusion, 0f, 0f, -Math.PI.toFloat() / 4, seconds = 1.0)
        val stable = fusion.wheelAngleDeg()
        val negated = axisAngle(0f, 0f, 1f, -45.0).map { -it }.toFloatArray()
        repeat(50) {
            feedRv(fusion, negated)
        }
        assertEquals(stable, fusion.wheelAngleDeg(), 0.05f)
    }

    @Test
    fun `re-zero captures the current grip as straight`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        feedGyro(fusion, 0f, 0f, -Math.PI.toFloat() / 2, seconds = 1.0)
        fusion.captureReference()
        assertEquals(0f, fusion.wheelAngleDeg(), 0.01f)
        // Turning back 90° is now -90 relative to the new reference.
        feedGyro(fusion, 0f, 0f, Math.PI.toFloat() / 2, seconds = 1.0)
        assertEquals(-90f, fusion.wheelAngleDeg(), 0.5f)
    }

    @Test
    fun `hysteresis holds the mode inside the band and switches at the edges`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        assertTrue(fusion.isFlatGrip())
        // 45° tilt (|n·up| ≈ 0.71) is inside the band → stays flat.
        feedRv(fusion, axisAngle(1f, 0f, 0f, 45.0))
        feedGyro(fusion, 0f, 0f, 0f, seconds = 0.01) // settles the correction
        assertTrue(fusion.isFlatGrip())
        // 55° tilt (≈ 0.57 < EXIT_FLAT) → cradle.
        feedRv(fusion, axisAngle(1f, 0f, 0f, 55.0))
        repeat(50) { feedRv(fusion, axisAngle(1f, 0f, 0f, 55.0)) }
        assertFalse(fusion.isFlatGrip())
        // Back inside the band (45°) → stays cradle.
        repeat(50) { feedRv(fusion, axisAngle(1f, 0f, 0f, 45.0)) }
        assertFalse(fusion.isFlatGrip())
        // Above ENTER_FLAT (35°, ≈ 0.82) → flat again.
        repeat(50) { feedRv(fusion, axisAngle(1f, 0f, 0f, 35.0)) }
        assertTrue(fusion.isFlatGrip())
    }

    @Test
    fun `manual flat override steers by yaw even in a cradled grip`() {
        val fusion = SensorFusion()
        fusion.axisMode = SensorFusion.AxisMode.FLAT
        feedRv(fusion, axisAngle(1f, 0f, 0f, 90.0)) // cradled
        fusion.captureReference()
        // Rotating about world −Z from this pose: body-frame rate is (0, −π/2, 0).
        feedGyro(fusion, 0f, -Math.PI.toFloat() / 2, 0f, seconds = 1.0)
        assertEquals(90f, fusion.wheelAngleDeg(), 0.5f)
    }

    @Test
    fun `before any estimate the angle is zero and stays sane`() {
        val fusion = SensorFusion()
        assertEquals(0f, fusion.wheelAngleDeg(), 0.001f)
        fusion.captureReference() // harmless before ready
        assertEquals(0f, fusion.wheelAngleDeg(), 0.001f)
    }

    @Test
    fun `no allocations in the hot path`() {
        val fusion = SensorFusion()
        feedRv(fusion, floatArrayOf(0f, 0f, 0f, 1f))
        fusion.captureReference()
        // Fixtures hoisted out of the measured block — only production code runs inside.
        val rvA = axisAngle(0f, 0f, 1f, -0.6)
        val rvB = axisAngle(0f, 0f, 1f, 0.6)
        warmUp {
            feedGyro(fusion, 0f, 0f, -1f, seconds = 0.1)
            fusion.wheelAngleDeg()
            feedRv(fusion, rvA)
        }
        val before = bytesUsed()
        repeat(2_000) {
            feedGyro(fusion, 0f, 0f, -1f, seconds = 0.01)
            feedRv(fusion, if (it % 2 == 0) rvA else rvB)
            fusion.wheelAngleDeg()
        }
        val grown = bytesUsed() - before
        // Smoke check only (a GC inside the loop can hide churn); the real
        // guarantee is the code review: no arrays are created in the event paths.
        assertTrue("allocated $grown bytes in 6000 hot-path calls", grown < 256 * 1024)
    }

    // --- allocation measurement helpers ---

    private inline fun warmUp(block: () -> Unit) {
        repeat(20) { block() }
        Runtime.getRuntime().gc()
        Thread.sleep(20)
    }

    private fun bytesUsed(): Long = run {
        val rt = Runtime.getRuntime()
        rt.totalMemory() - rt.freeMemory()
    }
}

package com.gyrophone.gyrophone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WheelModelTest {

    private fun model(
        range: Float = 900f,
        deadzone: Float = 0f,
        sensitivity: Float = 1f,
        curve: WheelModel.Curve = WheelModel.Curve.LINEAR
    ): WheelModel = WheelModel().apply {
        rangeDeg = range
        deadzoneDeg = deadzone
        this.sensitivity = sensitivity
        this.curve = curve
    }

    @Test
    fun `zero angle maps to center 128`() {
        assertEquals(128, model().apply(0f))
    }

    @Test
    fun `half range left and right map to the byte extremes`() {
        val m = model(range = 900f)
        assertEquals(255, m.apply(450f))
        assertEquals(1, m.apply(-450f))
    }

    @Test
    fun `beyond range clamps to the extremes`() {
        val m = model(range = 450f)
        assertEquals(255, m.apply(1000f))
        assertEquals(1, m.apply(-1000f))
    }

    @Test
    fun `quarter range maps to the exact linear byte`() {
        val m = model(range = 900f) // 225° = half of the ±450° half-range → n = 0.5
        assertEquals(128 + 64, m.apply(225f)) // round(127 · 0.5) = 64
        assertEquals(128 - 64, m.apply(-225f))
    }

    @Test
    fun `deadzone zeroes the band and rescales just outside it`() {
        val m = model(deadzone = 5f)
        assertEquals(128, m.apply(4.9f))
        assertEquals(128, m.apply(-4.9f))
        assertEquals(128, m.apply(5f)) // exactly dz is inside (a > -dz && a < dz)
        val out = m.apply(10f)
        assertTrue("expected small positive offset, was $out", out in 129..134)
    }

    @Test
    fun `deadzone keeps the extremes reachable`() {
        val m = model(range = 900f, deadzone = 5f)
        assertEquals(255, m.apply(450f))
        assertEquals(1, m.apply(-450f))
    }

    @Test
    fun `sensitivity scales the angle`() {
        assertEquals(128 + 64, model(sensitivity = 2f).apply(112.5f)) // 225° effective → n = 0.5
    }

    @Test
    fun `sensitivity above 1 clamps at full lock without wrapping`() {
        assertEquals(255, model(sensitivity = 3f).apply(160f))
        assertEquals(1, model(sensitivity = 3f).apply(-160f))
    }

    @Test
    fun `param setters coerce out-of-range values`() {
        val m = WheelModel()
        m.rangeDeg = 5000f
        m.deadzoneDeg = 99f
        m.sensitivity = 99f
        assertEquals(900f, m.rangeDeg, 0f)
        assertEquals(15f, m.deadzoneDeg, 0f)
        assertEquals(3.0f, m.sensitivity, 0f)
        m.rangeDeg = 1f
        m.sensitivity = 0.01f
        assertEquals(90f, m.rangeDeg, 0f)
        assertEquals(0.2f, m.sensitivity, 0f)
    }

    @Test
    fun `curve presets preserve the endpoints and the center`() {
        for (c in WheelModel.Curve.entries) {
            val m = model(curve = c)
            assertEquals("$c center", 128, m.apply(0f))
            assertEquals("$c right full", 255, m.apply(450f))
            assertEquals("$c left full", 1, m.apply(-450f))
        }
    }

    @Test
    fun `soft curve is more precise than linear near the center`() {
        val linear = model(curve = WheelModel.Curve.LINEAR).apply(45f)
        val soft = model(curve = WheelModel.Curve.SOFT).apply(45f)
        assertTrue("soft $soft should be closer to center than linear $linear", soft < linear)
    }

    @Test
    fun `sharp curve is more aggressive than linear near the center`() {
        val linear = model(curve = WheelModel.Curve.LINEAR).apply(45f)
        val sharp = model(curve = WheelModel.Curve.SHARP).apply(45f)
        assertTrue("sharp $sharp should be further from center than linear $linear", sharp > linear)
    }

    @Test
    fun `mapping is monotonic non-decreasing across the range`() {
        val m = model(range = 900f, deadzone = 1.5f, curve = WheelModel.Curve.SOFT)
        var previous = 0
        var angle = -460f
        while (angle <= 460f) {
            val b = m.apply(angle)
            assertTrue("non-monotonic at $angle°: $b < $previous", b >= previous)
            previous = b
            angle += 0.5f
        }
    }

    @Test
    fun `mapping is symmetric about the center`() {
        val m = model(range = 900f, deadzone = 1.5f, sensitivity = 1.3f, curve = WheelModel.Curve.SHARP)
        var angle = 0.5f
        while (angle <= 450f) {
            assertEquals(m.apply(-angle), 256 - m.apply(angle))
            angle += 0.5f
        }
    }
}

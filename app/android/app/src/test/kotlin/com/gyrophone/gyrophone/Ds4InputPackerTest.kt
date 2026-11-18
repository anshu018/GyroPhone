package com.gyrophone.gyrophone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Ds4InputPackerTest {

    @Test
    fun `neutral payload matches the golden bytes`() {
        val packer = Ds4InputPacker()
        val neutral = packer.currentPayload()
        // Sticks center, hat released, no buttons, pedals released.
        assertTrue(
            neutral.contentEquals(
                byteArrayOf(0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 0x80.toByte(), 0x08.toByte(), 0x00, 0x00, 0x00, 0x00)
            )
        )
    }

    @Test
    fun `first pack always sends and writes steering and pedals into the right bytes`() {
        val packer = Ds4InputPacker()
        val sent = packer.pack(steeringByte = 255, throttleByte = 200, brakeByte = 40)
        assertTrue(sent)
        val bytes = packer.currentPayload()
        assertEquals(255.toByte(), bytes[0])
        assertEquals(0x80.toByte(), bytes[1])
        assertEquals(0x80.toByte(), bytes[2])
        assertEquals(0x80.toByte(), bytes[3])
        assertEquals(0x08.toByte(), bytes[4])
        assertEquals(0x00.toByte(), bytes[5])
        assertEquals(40.toByte(), bytes[7]) // brake = L2 analog
        assertEquals(200.toByte(), bytes[8]) // throttle = R2 analog
    }

    @Test
    fun `identical state is deduped`() {
        val packer = Ds4InputPacker()
        assertTrue(packer.pack(128, 0, 0))
        assertFalse(packer.pack(128, 0, 0))
    }

    @Test
    fun `any changed byte re-sends`() {
        val packer = Ds4InputPacker()
        assertTrue(packer.pack(128, 0, 0))
        assertTrue(packer.pack(140, 0, 0))
        assertTrue(packer.pack(140, 0, 10))
        assertTrue(packer.pack(140, 20, 10))
    }

    @Test
    fun `counter advances in byte 6 bits 2 to 7 and wraps at 64`() {
        val packer = Ds4InputPacker()
        val seen = HashSet<Int>()
        for (i in 0 until 130) {
            packer.pack(128 + (i % 2), 0, 0) // alternate so every pack sends
            seen.add((packer.currentPayload()[6].toInt() and 0xFF) shr 2)
        }
        assertEquals(64, seen.size) // full 6-bit cycle seen = wrap happened
    }

    @Test
    fun `invalidateLastSent forces a resend of the identical state`() {
        val packer = Ds4InputPacker()
        assertTrue(packer.pack(200, 0, 0))
        assertFalse(packer.pack(200, 0, 0))
        packer.invalidateLastSent()
        assertTrue(packer.pack(200, 0, 0))
    }

    @Test
    fun `byte clamping cannot corrupt the report`() {
        val packer = Ds4InputPacker()
        packer.pack(-50, 300, 999)
        val bytes = packer.currentPayload()
        assertEquals(0.toByte(), bytes[0])
        assertEquals(255.toByte(), bytes[8])
        assertEquals(255.toByte(), bytes[7])
    }

    @Test
    fun `action buttons land in byte 4 high nibble and byte 5 with hat intact`() {
        val packer = Ds4InputPacker()
        // Cross = byte 4 bit 5 (0x20), L1 = byte 5 bit 0 (0x01), R1 = byte 5 bit 1 (0x02).
        packer.pack(150, 255, 0, faceBits = 0x20, miscBits = 0x03)
        val bytes = packer.currentPayload()
        assertEquals((0x08 or 0x20).toByte(), bytes[4]) // hat released + Cross
        assertEquals(0x03.toByte(), bytes[5]) // L1 + R1
        assertEquals(150.toByte(), bytes[0])
        assertEquals(255.toByte(), bytes[8]) // throttle
        assertEquals(0x00.toByte(), bytes[7]) // brake released
    }

    @Test
    fun `face bits can never corrupt the hat nibble`() {
        val packer = Ds4InputPacker()
        packer.pack(128, 0, 0, faceBits = 0xFF, miscBits = 0x00)
        val bytes = packer.currentPayload()
        assertEquals((0x08 or 0xF0).toByte(), bytes[4]) // low nibble stays hat=0x8
    }

    @Test
    fun `button release re-sends after dedupe`() {
        val packer = Ds4InputPacker()
        assertTrue(packer.pack(128, 0, 0, faceBits = 0x20, miscBits = 0x01))
        assertFalse(packer.pack(128, 0, 0, faceBits = 0x20, miscBits = 0x01))
        assertTrue(packer.pack(128, 0, 0, faceBits = 0x00, miscBits = 0x00))
        val bytes = packer.currentPayload()
        assertEquals(0x08.toByte(), bytes[4])
        assertEquals(0x00.toByte(), bytes[5])
    }
}

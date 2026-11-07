package com.gyrophone.gyrophone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Integrity tests for the byte-exact DS4 Bluetooth report descriptor
 * (docs/specs/M1-pair-as-ds4.md R4). These guard against transcription and
 * edit accidents; the device test remains the real gate.
 */
class Ds4DescriptorTest {
    private val descriptor = Ds4Descriptors.btReportDescriptor

    @Test
    fun `descriptor is exactly 356 bytes`() {
        assertEquals(356, descriptor.size)
    }

    @Test
    fun `descriptor opens with the gamepad application collection`() {
        assertArrayEquals(
            byteArrayOf(0x05, 0x01, 0x09, 0x05, 0xA1.toByte(), 0x01, 0x85.toByte(), 0x01),
            descriptor.copyOf(8),
        )
    }

    @Test
    fun `descriptor closes the application collection`() {
        assertArrayEquals(
            byteArrayOf(0xB1.toByte(), 0x02, 0xC0.toByte()),
            descriptor.copyOfRange(descriptor.size - 3, descriptor.size),
        )
    }

    @Test
    fun `full report 0x11 declares 77-byte input and output payloads`() {
        // Usage page 0xFF00, report ID 0x11, usage 0x20, logical 0..255,
        // size 8, count 0x4D (77), input; then usage 0x21 output.
        val anchor = "0600ff85110920150026ff007508954d810209219102"
        assertTrue(anchor in descriptor.toHex())
    }

    @Test
    fun `small input report 0x01 declares the standard gamepad usages`() {
        // Report ID 0x01, usages X/Y/Z/Rz, then hat switch with null state.
        val anchor = "85010930093109320935150026ff007508950481020939"
        assertTrue(anchor in descriptor.toHex())
    }

    @Test
    fun `sdp record matches the DS4 identity`() {
        assertEquals("Wireless Controller", Ds4Descriptors.SDP_NAME)
        assertEquals("Game Controller", Ds4Descriptors.SDP_DESCRIPTION)
        assertEquals("Sony Computer Entertainment", Ds4Descriptors.SDP_PROVIDER)
        assertEquals(0x08.toByte(), Ds4Descriptors.SDP_SUBCLASS)
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

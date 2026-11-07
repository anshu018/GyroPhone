package com.gyrophone.gyrophone

/**
 * Byte-exact artifacts of the DualShock 4 Bluetooth identity.
 *
 * The report descriptor below is transcribed from the SDP response of a real
 * DS4, dumped by eleccelerator (Frank Zhao, 18 January 2014) and hosted on
 * PSDevWiki: https://www.psdevwiki.com/ps4/DS4-BT (section "Service Discovery
 * Protocol (SDP)" -> "DS4" -> "Response", attribute 0x0206, length 0x0164).
 * The spec pins the same bytes: docs/specs/M1-pair-as-ds4.md (R3/R4).
 *
 * NEVER edit these bytes by hand. The descriptor is what makes Windows and
 * Steam read our reports as a DS4; any change invalidates the byte-faithful
 * contract (docs/ARCHITECTURE.md) and requires a device test before merge.
 *
 * The hex rows are formatted to match the spec dump line for line so a
 * reviewer can diff them visually.
 */
object Ds4Descriptors {
    /** SDP record fields, byte-faithful to the DS4's own record (spec R3). */
    const val SDP_NAME = "Wireless Controller"
    const val SDP_DESCRIPTION = "Game Controller"
    const val SDP_PROVIDER = "Sony Computer Entertainment"

    /**
     * HID Device subclass from the DS4's SDP record (attribute 0x0202 = 0x08).
     * Not Android's SUBCLASS2_GAMEPAD (0x02) — the DS4's own record is the
     * source of truth here.
     */
    const val SDP_SUBCLASS: Byte = 0x08

    /** Report IDs used in M1 (see docs/specs/M1-pair-as-ds4.md R5/R6). */
    const val REPORT_ID_INPUT_SMALL: Byte = 0x01
    const val FEATURE_ID_CALIBRATION: Byte = 0x02
    const val FEATURE_CALIBRATION_SIZE = 36

    /** Input report 0x01 payload size: sticks (4) + buttons (3) + triggers (2). */
    const val INPUT_SMALL_PAYLOAD_SIZE = 9

    private const val DESCRIPTOR_HEX = """
        05 01 09 05 A1 01 85 01 09 30 09 31 09 32 09 35
        15 00 26 FF 00 75 08 95 04 81 02 09 39 15 00 25
        07 75 04 95 01 81 42 05 09 19 01 29 0E 15 00 25
        01 75 01 95 0E 81 02 75 06 95 01 81 01 05 01 09
        33 09 34 15 00 26 FF 00 75 08 95 02 81 02 06 04
        FF 85 02 09 24 95 24 B1 02 85 A3 09 25 95 30 B1
        02 85 05 09 26 95 28 B1 02 85 06 09 27 95 34 B1
        02 85 07 09 28 95 30 B1 02 85 08 09 29 95 2F B1
        02 06 03 FF 85 03 09 21 95 26 B1 02 85 04 09 22
        95 2E B1 02 85 F0 09 47 95 3F B1 02 85 F1 09 48
        95 3F B1 02 85 F2 09 49 95 0F B1 02 06 00 FF 85
        11 09 20 15 00 26 FF 00 75 08 95 4D 81 02 09 21
        91 02 85 12 09 22 95 8D 81 02 09 23 91 02 85 13
        09 24 95 CD 81 02 09 25 91 02 85 14 09 26 96 0D
        01 81 02 09 27 91 02 85 15 09 28 96 4D 01 81 02
        09 29 91 02 85 16 09 2A 96 8D 01 81 02 09 2B 91
        02 85 17 09 2C 96 CD 01 81 02 09 2D 91 02 85 18
        09 2E 96 0D 02 81 02 09 2F 91 02 85 19 09 30 96
        22 02 81 02 09 31 91 02 06 80 FF 85 82 09 22 95
        3F B1 02 85 83 09 23 B1 02 85 84 09 24 B1 02 85
        90 09 30 B1 02 85 91 09 31 B1 02 85 92 09 32 B1
        02 85 93 09 33 B1 02 85 A0 09 40 B1 02 85 A4 09
        44 B1 02 C0
    """

    /** The DS4 Bluetooth HID report descriptor: exactly 356 bytes. */
    val btReportDescriptor: ByteArray = parseHex(DESCRIPTOR_HEX)

    private fun parseHex(hex: String): ByteArray {
        val clean = hex.replace(Regex("\\s+"), "")
        require(clean.length % 2 == 0) { "descriptor hex has an odd number of digits" }
        val out = ByteArray(clean.length / 2)
        for (i in out.indices) {
            val high = Character.digit(clean[2 * i], 16)
            val low = Character.digit(clean[2 * i + 1], 16)
            require(high >= 0 && low >= 0) { "descriptor hex has a non-hex digit at byte $i" }
            out[i] = ((high shl 4) or low).toByte()
        }
        return out
    }
}

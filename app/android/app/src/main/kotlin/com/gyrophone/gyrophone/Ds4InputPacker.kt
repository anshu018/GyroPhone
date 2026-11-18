package com.gyrophone.gyrophone

/**
 * Packs the DS4 small input report 0x01 (9-byte payload, M2 spec R4).
 *
 * Single report owner (ADR-012): this class owns the payload bytes, the
 * 6-bit send counter (byte 6, bits 2–7), and the report answered to
 * GET_REPORT. Ported 1:1 from the retired Dart `Ds4ReportPacker` semantics;
 * the Kotlin golden tests mirror the Dart suite.
 *
 * Streaming semantics (device finding 2026-11-19): a real DS4 streams its
 * report CONTINUOUSLY at its rate — it never goes silent when inputs are
 * still. The M1-era identical-report dedupe let the Bluetooth link idle
 * while the wheel sat still, Windows put the link into sniff mode, and the
 * first second of steering after an idle period crawled (user-reported ~1 s).
 * The packer therefore fills+advances on EVERY call; the sender sends every
 * tick while armed and linked, which keeps the link busy and the latency at
 * pure polling time.
 *
 * Byte map (M1 spec R5, community-verified — never "improve" it):
 * 0 steering (center 128) · 1–3 sticks at center · 4 hat released (0x8) ·
 * 5 buttons 0 · 6 counter · 7 brake/L2 · 8 throttle/R2.
 *
 * Confined to btExecutor.
 */
class Ds4InputPacker {

    private val payload = ByteArray(PAYLOAD_SIZE)
    private var counter = 0

    init {
        resetPayload()
    }

    /**
     * Fills the payload from the current state and advances the counter —
     * called every sender tick while armed and linked, matching real-DS4
     * continuous streaming. [faceBits]/[miscBits] carry the held DS4 button
     * contributions from the wheel layout's action buttons (byte 4 high
     * nibble / byte 5 — M2 layout v1.1).
     */
    fun pack(
        steeringByte: Int,
        throttleByte: Int,
        brakeByte: Int,
        faceBits: Int = 0,
        miscBits: Int = 0,
    ) {
        resetPayload()
        payload[0] = steeringByte.coerceIn(0, 255).toByte()
        payload[4] = (0x08 or (faceBits.coerceIn(0, 255) and 0xF0)).toByte()
        payload[5] = miscBits.coerceIn(0, 255).toByte()
        payload[7] = brakeByte.coerceIn(0, 255).toByte()
        payload[8] = throttleByte.coerceIn(0, 255).toByte()
        counter = (counter + 1) and COUNTER_MASK
    }

    /**
     * The report GET_REPORT must be answered with: the current streamed state
     * (neutral until the first send — M1 `lastInputReport` semantics). Returned
     * without a copy: both this path and `pack` run on btExecutor, and the
     * binder call marshals the bytes synchronously.
     */
    fun currentPayload(): ByteArray = payload

    private fun resetPayload() {
        payload[0] = 0x80.toByte()
        payload[1] = 0x80.toByte()
        payload[2] = 0x80.toByte()
        payload[3] = 0x80.toByte()
        payload[4] = 0x08.toByte() // hat: released
        payload[5] = 0x00
        payload[6] = ((counter and COUNTER_MASK) shl COUNTER_SHIFT).toByte()
        payload[7] = 0x00
        payload[8] = 0x00
    }

    companion object {
        const val PAYLOAD_SIZE = 9
        const val COUNTER_BYTE = 6
        const val COUNTER_SHIFT = 2
        const val COUNTER_MASK = 0x3F // 6 bits, wraps at 64 (M1 semantics)
    }
}

package com.gyrophone.gyrophone

/**
 * Packs the DS4 small input report 0x01 (9-byte payload, M2 spec R4).
 *
 * Single report owner (ADR-012): this class owns the payload bytes, the
 * 6-bit send counter (byte 6, bits 2–7), the identical-report dedupe, and the
 * cached report answered to GET_REPORT. Ported 1:1 from the retired Dart
 * `Ds4ReportPacker` semantics; the Kotlin golden tests mirror the Dart suite.
 *
 * Byte map (M1 spec R5, community-verified — never "improve" it):
 * 0 steering (center 128) · 1–3 sticks at center · 4 hat released (0x8) ·
 * 5 buttons 0 · 6 counter · 7 brake/L2 · 8 throttle/R2.
 *
 * Confined to btExecutor. `pack` returns true only when the wire changes;
 * a failed send must call [invalidateLastSent] so the host never holds a
 * stuck input (M1 semantics).
 */
class Ds4InputPacker {

    private val payload = ByteArray(PAYLOAD_SIZE)
    private val lastSent = ByteArray(PAYLOAD_SIZE)
    private var lastSentValid = false
    private var counter = 0

    init {
        resetPayload()
        System.arraycopy(payload, 0, lastSent, 0, PAYLOAD_SIZE)
    }

    /**
     * Fills the payload from the current state and reports whether it differs
     * from the last sent report (counter excluded). When true, the counter has
     * advanced and the caller must send.
     */
    fun pack(steeringByte: Int, throttleByte: Int, brakeByte: Int): Boolean {
        resetPayload()
        payload[0] = steeringByte.coerceIn(0, 255).toByte()
        payload[7] = brakeByte.coerceIn(0, 255).toByte()
        payload[8] = throttleByte.coerceIn(0, 255).toByte()
        if (lastSentValid && sameExceptCounter()) {
            return false
        }
        System.arraycopy(payload, 0, lastSent, 0, PAYLOAD_SIZE)
        lastSentValid = true
        counter = (counter + 1) and COUNTER_MASK
        return true
    }

    /** A failed/rejected send: the next identical state must be re-sent. */
    fun invalidateLastSent() {
        lastSentValid = false
    }

    /**
     * The report GET_REPORT must be answered with: the last accepted state
     * (neutral until the first send — M1 `lastInputReport` semantics). Returned
     * without a copy: both this path and `pack` run on btExecutor, and the
     * binder call marshals the bytes synchronously.
     */
    fun currentPayload(): ByteArray = lastSent

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

    private fun sameExceptCounter(): Boolean {
        for (i in 0 until PAYLOAD_SIZE) {
            if (i == COUNTER_BYTE) continue
            if (payload[i] != lastSent[i]) return false
        }
        return true
    }

    companion object {
        const val PAYLOAD_SIZE = 9
        const val COUNTER_BYTE = 6
        const val COUNTER_SHIFT = 2
        const val COUNTER_MASK = 0x3F // 6 bits, wraps at 64 (M1 semantics)
    }
}

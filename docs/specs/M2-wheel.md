# M2 spec — the wheel: gyro steering over the axis path

Milestone: [M2](../ROADMAP.md#m2--the-wheel-gyro-into-steam--not-started) · Ver-1 Steps 3–4 · Written 2026-11-11, presented for approval. This file is the source of truth for M2; code implements it.

## Goal

Real gyro steering — the product's identity — working in a real racing game without needing Steam's blessing. Steam classifies our device as Generic (M1 verdict, final), so the wheel reaches games the way every DirectInput wheel does: the phone fuses its sensors into a drift-free steering angle and sends it as a plain steering axis in input report `0x01`, which racing games like BeamNG and Assetto Corsa bind natively. This milestone also ships the wheel layout v1 (the first instance of the data-driven layout schema, [ADR-011](../DECISIONS.md)), folds in the M1 task 11 connect UI, and measures the sensor-path latency — the path where the <10 ms budget truly binds.

Two architecture decisions made with the user on 2026-11-11 shape everything below: the **sensor hot loop runs natively in Kotlin**, and wheel layout v1 is a **full cockpit** (wheel arc, re-zero, throttle/brake buttons, connection sheet, minimal settings).

## Requirements

### Scope

**In:** sensor fusion service, `WheelModel`, native hot loop, report `0x01` steering axis, wheel layout v1 + layout schema, connection sheet (bonded hosts + preserved pairing flow), minimal live settings, latency instrumentation, device tests.

**Out (unchanged from [ROADMAP.md](../ROADMAP.md) M2):** gamepad layout, haptics, the settings screen with persistence, car anything.

**Dropped from the ROADMAP M2 in-scope list:** the Steam Input template config — there is nothing to remap; the axis binds natively and Steam Input for generic controllers stays OFF (M1 finding). A short per-game binding guide is captured in this spec during device testing and ships with the APK at Step 9.

**Ver-1 Step 2 disposition:** Step 2 (DS4 hardening — complete the `0x11` map, verify Steam classification) is closed as obsolete by this spec. Its premise predates the 2026-11-08 classification verdict (Generic, final) and the declined full-descriptor experiment; the `0x11` motion-block path stays out of the product. Residue: output-report reception is already plumbed and logged (M1); real consumption (rumble) is M3. Ver-1.md is updated in the same change as this milestone's implementation.

### R1 — Native sensor hot loop (ADR-012, recorded when implementation starts)

- The hot path — sensor event → fusion → wheel model → report pack → send — runs entirely in Kotlin. Zero platform-channel crossings and zero allocations per sensor event ([ARCHITECTURE.md](../ARCHITECTURE.md) invariants 6, performance budget).
- Thread split: a dedicated `HandlerThread` delivers sensor events and runs fusion only. `btExecutor` (the existing `"gyrophone-hid"` thread — all Bluetooth work stays on it, M1 invariant) owns everything report-related: wheel-model application, packing, dedupe, counter, `lastInputReport`, sends, and parameter updates. All report state is therefore single-threaded.
- The sensor thread posts the fused pre-model angle (a scalar) to `btExecutor`, which packs and sends at the ≤120 Hz cap with latest-state semantics: every send carries the freshest angle; nothing stale is queued and no frames are batched or skipped ([ARCHITECTURE.md](../ARCHITECTURE.md) report-rate rule).
- **One report owner.** The native packer owns report `0x01` bytes, the send counter, the dedupe state, and `lastInputReport` (the GET_REPORT cache, unified). The Dart send path (`Ds4ReportPacker`, `HidBridge.sendState`, touch sticks) retires with the M1 status screen — two writers would corrupt the counter and dedupe. The Dart packer and its golden tests retire 1:1 into the Kotlin suite.
- Failure semantics preserved (now native): the sender gates on the HID connection state; a rejected or failed `sendReport` invalidates the dedupe state so hosts never hold stuck inputs; the invalidation runs on `btExecutor`.
- New channel methods (Dart → Kotlin): `setWheelParams`, `reZero`, `setPedals`, `setStreaming` (arm/disarm). Live-apply, no re-registration, no reconnect.
- Focus-loss neutralization extends to sensor-derived bytes: on pause/hidden the loop is disarmed and a neutral report is sent (steering centered, pedals released) — extends the M1 rule.

### R2 — Sensor fusion (`SensorFusion`, Kotlin)

| Input | Sensor | Rate |
|-------|--------|------|
| Fast path | `TYPE_GYROSCOPE` | `SENSOR_DELAY_FASTEST` |
| Drift correction | `TYPE_ROTATION_VECTOR` | `SENSOR_DELAY_FASTEST` |

- Algorithm class: complementary fusion. Gyro integrates the orientation quaternion event-by-event (low latency); each rotation-vector event nudges the estimate toward it (small fixed gain — drift correction). All math allocation-free; quaternion and vector objects are reused.
- The wheel angle is the rotation component about the wheel axis of the relative orientation (re-zero reference ⊗ current estimate).
- **Wheel axis, gravity-aware:** near-flat grip → rotation about world up (yaw); cradled grip → rotation about the horizontal screen normal. Hysteresis around the tilt boundary prevents mode flip-flop. A manual override setting (flat / cradle) covers other grips — axis selection is a setting from day one, never an assumption (Ver-1 Step 3 pitfall).
- Rotation vector is the default source (magnetometer-corrected yaw). The 10-minute drift test decides whether magnetometer wobble forces the `TYPE_GAME_ROTATION_VECTOR` fallback; the decision is recorded here and in [RESEARCH.md](../RESEARCH.md) either way.
- **Manifest: `HIGH_SAMPLING_RATE_SENSORS` is declared** (normal, install-time permission). Apps targeting Android 12+ are rate-limited to 200 Hz through `registerListener` without it, and requesting a higher rate raises `SecurityException` ([Android sensor rate-limiting](https://developer.android.com/guide/topics/sensors/sensors_overview#sensors-rate-limiting), verified 2026-11-11; fact recorded in [RESEARCH.md](../RESEARCH.md)).
- Fusion runs at the gyro event rate (≥100 Hz required; the real rate is measured on-device — `SENSOR_DELAY_FASTEST` is a request, not a guarantee). The sender samples fused state at ≤120 Hz.
- Sensor coordinates follow the device's **natural** orientation (portrait on our phones), never the app's landscape lock — axis math uses the sensor frame, not the screen frame ([sensor coordinate system](https://developer.android.com/guide/topics/sensors/sensors_overview#sensors-coord)).

### R3 — WheelModel (Kotlin, pure math, exhaustively JVM-tested)

- Configurable range 90°–900°, default 900°. Quantization constraint, documented honestly: the axis is 8-bit (255 distinct positions across ±range/2), so 900° ≈ 3.53°/step; games smooth, and the response curve shapes the center. If the drive test feels quantization, the fallback is a lower default range (450° ≈ 1.76°/step) — range is configurable either way.
- Pipeline order: re-zeroed angle → deadzone (physical degrees near zero, rescaled outside) → sensitivity multiplier → response curve (monotonic, symmetric, endpoints preserved) → clamp to ±range/2 → byte mapping `128 + round(127 · clamped/(range/2))`.
- Re-zero captures the current fused orientation as the reference (marshaled to the sensor thread) and resets model state (angle 0, filter state cleared) — a stale reference would reintroduce the offset it exists to clear.

### R4 — Report `0x01` wiring (byte-faithful)

No descriptor change. The 79-byte small descriptor stays exactly as registered in M1 ([M1 spec R4](M1-pair-as-ds4.md)); steering rides an existing axis usage. The packing change is still device-tested before merge (byte-faithfulness rule).

| Offset | Content in M2 |
|--------|---------------|
| 0 | **Steering** — fused wheel angle, unsigned, center 128 |
| 1–3 | Center 128 (unused sticks) |
| 4 | Hat released (`0x8` low nibble), no buttons |
| 5 | 0 (no buttons) |
| 6 | PS/touchpad bits 0, counter advances per wire send |
| 7 | **Brake** — L2 analog (0 released) |
| 8 | **Throttle** — R2 analog (0 released) |

- **Axis choice: byte 0, the X usage.** Rationale: gamepad presets bind steering to left-stick X on a DS4-named device, and DirectInput wheels most commonly expose X. Rz (byte 3) is the documented fallback if a target game's auto-bind misses X — a one-byte parameter, not a descriptor change.
- The `0x11` motion-block path stays out — it is tied to the declined full-descriptor experiment and is not revisited in M2.

### R5 — Pedals (touch)

- THROTTLE and BRAKE hold buttons on the wheel screen map to bytes 8 and 7 (R2/L2 analog, 0 released → 255 full).
- Touch events cross the channel Dart → Kotlin via `setPedals` (touch rate is low; the channel is fine here) and the native owner merges them into the report. Release returns the byte to 0; dedupe sends the change. Focus loss releases both.

### R6 — Dart bridge extensions (`HidBridge`)

- The M1 lifecycle state machine is unchanged, semantics and tests preserved. The `streaming` transition is still "first send observed", now triggered by native send activity instead of a Dart send.
- New methods: `setWheelParams(range, deadzone, sensitivity, curve, axisMode)`, `reZero()`, `setPedals(throttle, brake)`, `setStreaming(enabled)`.
- UI state: a new dedicated lightweight stream, throttled native-side to ≤60 Hz, carrying the fused angle (plus latency stats for the readout). The sensor-rate hot path never touches the shared lifecycle event sink.

### R7 — Wheel layout v1, first instance of the layout schema ([ADR-011](../DECISIONS.md))

- **The schema:** Dart sealed-class definitions — `LayoutDefinition` (id, name, widgets) over widget specs (`WheelSpec`, `HoldButtonSpec`, `StatusChipSpec`, `LabelSpec`), positions normalized 0–1 (resolution-independent), HID bindings expressed as DS4 targets (steering axis, analog trigger, button bit). The schema is the contract; the wheel layout is its first instance, defined as data and rendered by one layout engine. Step 6's gamepad layout and M3's switcher/remapping ride the same schema.
- **The wheel instance:** full-screen wheel arc mirroring the fused angle at the UI stream rate — `ValueNotifier` + `CustomPainter`, no animation curves (Ver-1 Step 4 pitfall; 1-frame reaction budget); THROTTLE/BRAKE hold buttons; re-zero button; connection chip; latency readout; settings entry. Landscape lock stays (manifest).

### R8 — Connection sheet (M1 task 11 fold-in) and minimal settings

- Bonded-hosts list with a Connect action — the bridge's `getHosts`/`connect` already exist; this surfaces device-initiated connect for "paired before, profile added after". First-time phone-side discovery stays deferred to M3 (M1 task 11 scope).
- The proven first-time pairing flow is preserved and reachable: "Make discoverable" and the PC pairing instructions migrate from the M1 status screen into the connection sheet. Never removed.
- Minimal settings sheet: range, deadzone, sensitivity, response-curve preset, axis mode — live-apply, no persistence (persistence is M3, Step 7). Latency readout (avg/p95/n).

### R9 — Measurements (recorded here, then [RESEARCH.md](../RESEARCH.md))

- **Sensor-path latency** (Nord 5 primary): sensor-event timestamp → `sendReport` accepted; ring buffer (~128 samples), avg/p95, shown in the latency readout, recorded against the <10 ms budget. The M1 touch-path numbers (avg 7.85 ms, p95 23.93 ms) remain the recorded touch-path figures.
- **Real sensor rates** on both devices (gyro + rotation vector, Hz).
- **Drift:** 10-minute session, no manual re-zero; residual drift recorded.

## Acceptance criteria

Mirrors [ROADMAP.md](../ROADMAP.md) M2, re-framed to the axis path (ROADMAP M2's section text is updated in the same change). A box is ticked only after the criterion passes on hardware.

- [ ] M2 spec written and approved
- [ ] The fused wheel angle drives the steering axis of report `0x01`, and BeamNG or Assetto Corsa steers with it bound natively in-game (no Steam Input remapping)
- [ ] Rotation range (up to 900°), deadzone, and sensitivity are configurable and take effect live
- [ ] Re-zero works and is reachable during play
- [ ] No manual re-zero needed during a 10-minute session (drift check)
- [ ] Sensor-path latency measured and recorded against the <10 ms budget in [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ ] Device test passes per the byte-faithfulness rule; sensor path verified on the second device
- [ ] `flutter analyze`, `flutter test`, and `gradlew testDebugUnitTest` green

## Task list

1. Record [ADR-012](../DECISIONS.md) (native hot loop, native report ownership) in the same change as the first implementation commit.
2. Kotlin `SensorFusion` (R2) + JVM tests — property-based: axis projection, complementary correction, re-zero, antipodal quaternion handling.
3. Kotlin `WheelModel` (R3) + JVM tests — order-of-pipeline, range/clamp/deadzone/curve/byte mapping.
4. Kotlin `Ds4InputPacker` (R4): port the `0x01` pack; unify counter/dedupe/`lastInputReport`; golden-byte tests mirroring the retired Dart suite.
5. Wire the hot loop in `HidPlugin.kt` (R1, R4–R6): sensor thread, fusion → model → pack → send at ≤120 Hz, new channel methods, latency ring, ≤60 Hz UI stream; retire the Dart send path and touch sticks; extend focus-loss neutralization.
6. Dart: layout schema + engine + wheel layout instance (R7); connection sheet, settings sheet, latency readout (R8); bridge extensions (R6).
7. Gates green; install on Nord 5 (USB adb) and Nothing Phone 1 (wireless adb).
8. Device tests per R9: joy.cpl axis sweep (byte-faithfulness), BeamNG/Assetto Corsa bind + drive, 10-minute drift, latency recording, second-device sanity. Capture the per-game binding steps for the Step 9 guide.
9. Docs in the same change as the work they describe: [ARCHITECTURE.md](../ARCHITECTURE.md) (module map — sensors native, report owner, data flows), [ROADMAP.md](../ROADMAP.md) M2 re-frame + ticks for passed criteria, [Ver-1.md](../../Ver-1.md) (Step 2 closed obsolete, Steps 3–4 statuses), [STATUS.md](../../STATUS.md), [RESEARCH.md](../RESEARCH.md) findings; commit and push.

## Pitfalls (do not)

Pre-filled from the [M1 spec](M1-pair-as-ds4.md), [RESEARCH.md](../RESEARCH.md), and the M1 code review; appended in-session during the work.

- Do not touch the descriptor. The 79-byte small descriptor is the shipping artifact; the `0x11` motion-block path is tied to the declined full-descriptor experiment and stays out. Steering rides the existing X usage — a packing change, not a descriptor change.
- Do not keep two report writers. The Dart packer and `sendState` must retire with the M1 status screen; two writers corrupt the counter, dedupe, and `lastInputReport`.
- Do not run sensor work on the main/UI thread. Sensor delivery gets its own `HandlerThread`; Bluetooth calls stay on `btExecutor` (M1 invariant). All report state lives on one thread.
- Do not allocate per sensor event — reuse quaternion, vector, and byte-buffer objects. Channel decode allocates per event, which is exactly why the hot loop is native (invariant 6).
- Do not batch, skip, or queue stale reports. The sender caps at 120 Hz with latest-state semantics; every send carries the freshest angle ([ARCHITECTURE.md](../ARCHITECTURE.md) report-rate rule).
- Do not integrate raw gyro for the wheel angle alone — it drifts; the rotation vector is the correction source.
- Handle rotation-vector antipodal sign flips (q and −q are the same rotation) — naive blending wobbles when the source flips sign.
- Units: gyro is rad/s; the rotation vector is a quaternion (device→world, w,x,y,z). Mixing these reads as "wheel moves at the wrong speed" or swapped axes.
- Sensor coordinates follow the device's natural orientation (portrait on our phones), not the app's landscape lock — projecting the wheel axis in the screen frame breaks the math in landscape.
- Re-zero must reset the whole filter state, not just the reported angle — a stale reference reintroduces the offset it exists to clear.
- Extend focus-loss neutralization to sensor-derived bytes and pedals — a paused app must never leave a held steering angle or pressed throttle in the game.
- Do not flood the shared lifecycle event sink with sensor-rate data — the UI angle stream is a separate, throttled path.
- Axis-mode selection near the tilt boundary flips without hysteresis — use a hysteresis band, not a raw threshold.
- Magnetometer interference (monitors, motors, magnetic car mounts) can wobble rotation-vector yaw — the drift test decides the `GAME_ROTATION_VECTOR` fallback; do not pre-optimize.
- Verify the real sensor rate on both devices by logging it — `SENSOR_DELAY_FASTEST` is a request, not a guarantee.
- Do not register gyro-class sensors without `HIGH_SAMPLING_RATE_SENSORS` on a target-31+ app: delivery is capped at 200 Hz, and requesting more throws `SecurityException` (verified against the Android docs, 2026-11-11). A device's mic-privacy toggle can cap sensors regardless of the permission — a debugging data point, not an app bug.
- Do not remove the proven pairing flow — "Make discoverable" and the PC pairing instructions migrate into the connection sheet, they do not disappear.
- A rejected send to a merely-registered host still errors native-side — gate sends on the connected state and invalidate dedupe on any failure (M1 semantics, now native).
- Do not claim the <10 ms budget met without the recorded measurement (never-do #9).

## Lessons learned

Filled in when the milestone closes.

## Open questions

1. `ROTATION_VECTOR` vs `GAME_ROTATION_VECTOR` — decided by the 10-minute drift test during implementation; recorded here and in [RESEARCH.md](../RESEARCH.md) either way.
2. Whether 8-bit quantization (~3.53°/step at 900°) is felt in-game — decided by the drive test; fallback is a lower default range. The range is configurable either way.
3. Whether the X axis suffices for auto-binding in both target games or Rz is needed — decided by the binding test; the byte is a parameter, not a descriptor change.

# Ver-1 — GyroPhone app (PC games): execution plan & tracker

The detailed build plan for **Version 1.0** — the GyroPhone Android app that turns a phone into a 900° gyro steering wheel + haptic gamepad for PC games over Bluetooth HID. Any agent, even with zero conversation memory, can execute V1 from this file.

**Version map:** v1.0 = this app (PC games) → v2.0 = ESP32 retrofit board for any RC car → v3.0 = our designed FPV car. Sequence rationale: [ADR-003](docs/DECISIONS.md).

## Cold-start protocol (new agent? do this in order)

1. Read [STATUS.md](STATUS.md) — the in-flight task and blockers
2. Read [PERSONA.md](PERSONA.md) — who you are while working
3. Read this file: the tracker table, then **only your current step** in full
4. Read that step's milestone spec in `docs/specs/` (spec-first rule; if the spec doesn't exist yet, writing it is your first task)
5. Follow the session protocol in [AGENTS.md](AGENTS.md) — and update this file's step statuses as work completes

## Tracker

| # | Step | Milestone | Depends on | Status |
|---|------|-----------|------------|--------|
| 0 | Project scaffold | M1 prep | — | DONE (device install check folds into Step 1 device tests) |
| 1 | HID transport spike (phone pairs as DS4) | M1 | 0 | DONE |
| 2 | DS4 hardening (byte-faithful report layer) | M2 prep | 1 | NOT STARTED |
| 3 | Sensor pipeline (fusion + wheel model) | M2 | 2 | NOT STARTED |
| 4 | Wheel layout v1 | M2 | 3 | NOT STARTED |
| 5 | Haptic engine (rumble replay) | M3 | 2 | NOT STARTED |
| 6 | Gamepad layout + layout switcher | M3 | 4 | NOT STARTED |
| 7 | Settings + persistence | M3 | 4, 5 | NOT STARTED |
| 8 | Onboarding + polish (the stranger test) | M3 | 6, 7 | NOT STARTED |
| 9 | Ship artifacts (APK, Steam guide, v0.1.0) | M3 close | 8 | NOT STARTED |

Update statuses as work completes: `NOT STARTED → IN PROGRESS → DONE`. Never mark DONE without the step's exit criteria passing.

## Ground rules

- Scope guards: no iOS, no online multiplayer, no theming, no PC-side drivers, no car code. Non-goals in [docs/VISION.md](docs/VISION.md) are law.
- Spec-first: each milestone gets a spec in `docs/specs/` before code (template in [docs/specs/README.md](docs/specs/README.md), including the **Pitfalls** section — pre-fill it from this file's step pitfalls and append discoveries in-session).
- Byte-faithfulness rule and performance budgets in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) are binding.
- Devices: primary **OnePlus Nord 5**, secondary **Nothing Phone 1** (OEM-quirk check). An emulator cannot substitute — `BluetoothHidDevice` needs real Bluetooth hardware.
- V1 definition of done: a stranger installs nothing on their PC, pairs their phone, and drives a Steam racing game with gyro + rumble inside five minutes, unaided.

---

## Step 0 — Project scaffold

**Status: IN PROGRESS** (analyze/test green 2026-11-07; device install pending USB debugging) · Milestone: M1 prep · Depends on: —

**Goal:** a clean, enforced project structure so every later step lands in the right place.

**Tasks:**
- [x] `flutter create` in `app/` with org `com.gyrophone.app` (`--org com.gyrophone --project-name gyrophone`), minSdk **28** in `android/app/build.gradle` (the `BluetoothHidDevice` floor — do not leave the default) — note: the create command yields `com.gyrophone.gyrophone`; the applicationId was edited to `com.gyrophone.app` after scaffold (see M1 spec R1)
- [x] Strict analysis: `flutter_lints` (or stricter) enabled, zero findings
- [x] `.gitattributes` at repo root: `* text=auto eol=lf` (ends the CRLF warnings)
- [ ] Verify Gradle/JDK: system Java is 22 — if Gradle objects, pin `org.gradle.java.home` for this project; do not change the system Java
- [ ] Confirm `flutter doctor` stays green; `flutter devices` sees a connected phone once USB debugging is enabled
- [x] Commit: `chore: scaffold flutter app (com.gyrophone.app, minSdk 28)`

**Exit when:** `flutter analyze` and `flutter test` pass on a fresh clone; app builds and installs on the Nord 5 (`flutter run`).

**Pitfalls (do not):**
- Do not accept default minSdk 21 — HID device mode silently fails below API 28.
- Do not rename the package after scaffolding — `flutter create` bakes it into Kotlin/Gradle files; decide now.
- Do not commit `local.properties`, keystores, or `.gradle/` (root `.gitignore` covers these — verify before first app commit).
- Do not "fix" Java 22 by upgrading/downgrading the system JDK — pin per-project only.

---

## Step 1 — HID transport spike (phone pairs as DS4)

**Status: DONE** (2026-11-08 — all M1 acceptance criteria passed on two devices) · Milestone: M1 · Depends on: 0

**Goal:** prove the kill-switch assumption — a phone can pose as a DualShock 4 on the PC, with buttons and sticks working.

**Tasks:**
- [x] Write the M1 spec first: `docs/specs/M1-pair-as-ds4.md` (goal, requirements, byte maps, acceptance criteria, task list, pitfalls) — user approval before code
- [x] `HidPlugin.kt`: request `BLUETOOTH_CONNECT` runtime permission (API 31+), then `BluetoothHidDevice.registerApp` with a DS4 SDP app record + the community-documented DS4 report descriptor (byte-exact — do not write the descriptor from memory) — descriptor facts: the full 356-byte DS4 descriptor is kept for Step 2; M1 registers the DS4's own 79-byte small-report descriptor (device-test finding, see spec R4/Pitfalls)
- [x] Connection state machine (Dart `HidBridge`): unpaired → registered → connected → streaming → error, with transitions logged — plus device-initiated bounded reconnect and in-app discoverable request (device findings)
- [x] Input-report packing: sticks (unsigned bytes, center 128) + buttons (bit fields) — **into report `0x01` for M1, not `0x11`** (spec R5: Windows' in-box stack parses only `0x01`'s standard usages; the `0x11` switch happens in Step 2, faithful to real-DS4 calibration-triggered behavior)
- [x] Minimal temporary status screen (per [docs/UIUX.md](docs/UIUX.md) interim rule): BT state, device name, guide to pair from PC
- [x] Test on Nord 5 + Nothing Phone 1; verify in a Windows gamepad tester (joy.cpl and/or gamepad-tester.com) via Steam-off first, then Steam — **both done 2026-11-08: Nord 5 and Nothing Phone 1 both pair, connect, and drive joy.cpl correctly; Steam lists both as "Sony Computer Entertainment Wireless Controller" and its mapping wizard ran with PlayStation-style input names**
- [x] Measure input-path latency against the <10 ms budget ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)); record numbers in the spec — **avg 7.85 ms (within budget), p95 23.93 ms (flagged for Step 2)**

**Exit when:** ROADMAP M1 acceptance criteria all pass (two devices, tester-visible inputs, reconnect survives, latency recorded).

**Pitfalls (do not):**
- Do not request permissions lazily — `BLUETOOTH_CONNECT` must be granted *before* `registerApp`, or registration fails silently on Android 12+.
- Do not invent the report descriptor — source the real DS4 descriptor from the community-documented byte map and verify the report IDs (`0x11` input / `0x05` output).
- Do not assume bonding direction: the PC pairs to the phone; handle the case where the host initiates vs the app calling `connect()` after bonding.
- Do not ship HID changes without a device test — Steam misreading the map invalidates everything downstream (byte-faithfulness rule).
- Do not run BT work on the UI thread; state transitions go to the logger, not toasts.

---

## Step 2 — DS4 hardening (byte-faithful report layer)

**Status: NOT STARTED** · Milestone: M2 prep · Depends on: 1

**Goal:** make Steam believe, completely, that this is a DS4 — the precondition for gyro.

**Tasks:**
- [ ] Complete the `0x11` map: 6-axis motion block present (even with placeholder data), timestamp, battery nibble wired to the phone's real battery
- [ ] Golden-byte unit tests for the packer (fixed inputs → expected byte arrays, endianness asserted)
- [ ] Verify Steam classifies the device as a DS4 (Steam → Settings → Controller); capture what works and what's missing in the spec
- [ ] Output-report reception (`onOutputReport`) plumbed end-to-end and logged (real consumption happens in step 5)

**Exit when:** Steam shows a DS4 with correct sticks/buttons; packer tests prove byte-faithfulness; output reports arrive and are logged.

**Pitfalls (do not):**
- Motion values are **signed 16-bit little-endian**; sticks are unsigned bytes centered at 128 — mixing these up shows up as "gyro works but sticks are dead" or vice versa.
- Do not batch or skip reports to save work — stale motion reads as lag.
- Do not parse output reports on the BT callback thread beyond extraction — hand off to the haptics pipeline.

---

## Step 3 — Sensor pipeline (fusion + wheel model)

**Status: NOT STARTED** · Milestone: M2 · Depends on: 2

**Goal:** real steering — drift-free wheel angle and motion data at sensor rate.

**Tasks:**
- [ ] Write the M2 spec (`docs/specs/M2-wheel.md`) — user approval first
- [ ] `SensorFusionService`: rotation vector (drift correction) + gyroscope (rate) fused into the wheel angle; sensor registered at ≥100 Hz (`SENSOR_DELAY_FASTEST`-class, not `GAME`)
- [ ] `WheelModel`: steering-axis choice (gravity-aware default + manual override), configurable range up to 900°, deadzone, response curve, re-zero
- [ ] Populate the motion block with real fused values at the report rate
- [ ] Unit tests: fusion math, range/clamp/curve/deadzone, re-zero behavior (no allocations in the hot loop)

**Exit when:** ROADMAP M2 acceptance criteria pass — Steam receives gyro, template config steers a racing game, no manual re-zero needed in a 10-minute session.

**Pitfalls (do not):**
- Do not use the default sensor delay — `SENSOR_DELAY_GAME` is ~50 Hz; steering needs ≥100 Hz.
- Do not integrate raw gyro for the wheel angle alone — it drifts; the rotation vector is the correction source.
- The wheel axis depends on grip (cradle vs. handheld): axis selection is a setting from day one, not an assumption.
- Zero allocations per sensor event — GC pauses read as input stutter (invariant #6).

---

## Step 4 — Wheel layout v1

**Status: NOT STARTED** · Milestone: M2 · Depends on: 3

**Goal:** a usable racing cockpit screen — functional first, styling temporary ([docs/UIUX.md](docs/UIUX.md) interim rule).

**Tasks:**
- [ ] Define the declarative layout schema (per [ADR-011](docs/DECISIONS.md)) in the M2 spec: widget types, positions, HID bindings — **the schema is the spec; the wheel is its first instance**
- [ ] Layout engine renders the schema; wheel arc mirrors the real angle at sensor rate (bypass animation curves)
- [ ] Re-zero button, connection status, minimal debug settings (range/sensitivity) on-screen
- [ ] Verify the on-screen wheel stays in sync under 10-minute play (no drift between feel and render)

**Exit when:** the user drives BeamNG/Assetto Corsa with the phone wheel and the on-screen wheel matches reality.

**Pitfalls (do not):**
- Do not `setState` per sensor event at 120 Hz — use a `ValueNotifier`/custom painter path; UI jank reads as input lag.
- Do not hardcode the wheel screen — it must render from the schema, or step 6's engine work doubles.

---

## Step 5 — Haptic engine (rumble replay)

**Status: NOT STARTED** · Milestone: M3 · Depends on: 2

**Goal:** game rumble becomes phone vibration — the first "nobody has this" feature.

**Tasks:**
- [ ] Write the M3 spec (`docs/specs/M3-feel.md`) — user approval first
- [ ] `HapticEngine`: consume `0x05` output reports (two motor intensities) → `VibrationEffect` waveforms; amplitude-capability detection with graceful degradation
- [ ] Rate-limit and map intensities so levels are distinguishable by feel
- [ ] Independent thread/channel from the control path — haptics never block input (invariant #5)
- [ ] Unit tests for pattern selection; feel test logged from a real game session

**Exit when:** rumble from a Steam game is felt on the phone, levels distinguishable, control latency unaffected.

**Pitfalls (do not):**
- Do not call Vibrator from the BT callback thread — marshal to a dedicated path.
- Amplitude control is not universal — test without it (many devices quantize to few levels); degrade, don't crash.
- VIBRATE permission must be in the manifest from the first build that touches haptics.

---

## Step 6 — Gamepad layout + layout switcher

**Status: NOT STARTED** · Milestone: M3 · Depends on: 4

**Goal:** the second skin proves the engine — twin-stick layout riding the same schema.

**Tasks:**
- [ ] Gamepad layout definition: twin sticks, ABXY, D-pad, triggers, shoulders (byte mappings per the DS4 map)
- [ ] In-app layout switcher (wheel ↔ gamepad) per [ADR-011](docs/DECISIONS.md)
- [ ] Basic button remapping in settings (rebind which control sends which DS4 button)

**Exit when:** ROADMAP M3 criteria pass for layouts: switchable in-app, remappable in settings, both layouts drive a real game.

**Pitfalls (do not):**
- Do not let remapping desync the Steam template config — remaps change what the phone sends, and the DS4 map is fixed; remap *controls → DS4 buttons*, never DS4 buttons → console outputs.
- Do not build the drag-and-drop editor — parked by [ADR-011](docs/DECISIONS.md); scope creep here delays shipping.

---

## Step 7 — Settings + persistence

**Status: NOT STARTED** · Milestone: M3 · Depends on: 4, 5

**Goal:** every knob the earlier steps proved necessary, persisted and live.

**Tasks:**
- [ ] Settings screen: rotation range, sensitivity, deadzone, response curve, steering axis, haptics on/off/intensity, re-zero preference
- [ ] Persistence via `shared_preferences` (or Hive if the schema grows), normalized values, applied live without reconnect
- [ ] Auto-reconnect behavior on app relaunch and BT drop

**Exit when:** all settings take effect immediately, survive restart, and the app reconnects cleanly.

**Pitfalls (do not):**
- Do not store raw UI strings for numeric settings — persist normalized values with defaults for missing keys.
- Do not apply settings by recreating the HID registration — reconnects are user-visible; live-apply where the pipeline allows.

---

## Step 8 — Onboarding + polish (the stranger test)

**Status: NOT STARTED** · Milestone: M3 · Depends on: 6, 7

**Goal:** the 5-minute promise, provable with a human who has never seen the app.

**Tasks:**
- [ ] First-run walkthrough: grant permissions → enable BT → pair from PC (deep-link to Bluetooth settings via platform channel) → verify → play
- [ ] Connection-loss overlay: calm full-screen state with auto-retry ([docs/UIUX.md](docs/UIUX.md) constraint)
- [ ] App identity: name GyroPhone, icon, in-app version display
- [ ] Run the stranger test: one person, no help, install → drive in five minutes; log where they stuck

**Exit when:** the unaided stranger test passes; all stuck-points fixed or made impossible.

**Pitfalls (do not):**
- Do not write onboarding text before the flow is real — walk the actual pairing path with the device first.
- Do not skip the stranger test because "it's obvious" — every untested onboarding step is a support ticket later.

---

## Step 9 — Ship artifacts

**Status: NOT STARTED** · Milestone: M3 close · Depends on: 8

**Goal:** a tagged, signed, documented V1 that a stranger can install.

**Tasks:**
- [ ] Generate the release keystore locally (`keytool`), store **outside the repo**, configure signing — never committed (never-do #3)
- [ ] Signed release APK; version `0.1.0+1` in pubspec; tag `v0.1.0`
- [ ] Steam Input template config file + setup guide (with screenshots) shipped alongside the APK
- [ ] `CHANGELOG.md` born (Keep-a-Changelog categories); README status log updated; final V1 demo video recorded

**Exit when:** V1 is installed from the APK by someone who didn't build it, and works end-to-end.

**Pitfalls (do not):**
- Do not generate the keystore inside the project folder, and do not lose it — it is the update identity for the app's lifetime.
- Do not publish to a store yet — store release process is in the parking lot; this ships as a direct APK.

---

## Progress log (append-only)

| Date | Event |
|------|-------|
| 2026-11-07 | Ver-1 plan written; all steps NOT STARTED |
| 2026-11-07 | M1 spec written and approved (`docs/specs/M1-pair-as-ds4.md`); transport research recorded in RESEARCH.md |
| 2026-11-07 | Step 0 scaffold: app/ created (com.gyrophone.app, minSdk 28), analyze/test green; device install pending |
| 2026-11-07 | Step 1 spike implemented: DS4 SDP + byte-exact 356-byte BT descriptor (independently verified), HidPlugin.kt, Dart state machine + 0x01 packer + status screen; analyze zero findings, 23/23 Dart tests, 6/6 Kotlin descriptor tests, APK builds; NDK 28.2 installed; device tests next |
| 2026-11-08 | Device test on Nord 5 (Android 16): control experiment (blugaemand) proved the platform; our app's payload iterated to working state — in-app discoverable request + DS4 small-report descriptor (79 B) + device-initiated reconnect; **transport proven: pairs, connects, sticks+buttons correct in joy.cpl, Steam lists the controller**. Findings recorded in spec Pitfalls + RESEARCH.md; latency readout, Steam verdict, and Nothing Phone 1 test remain |
| 2026-11-08 (late) | **M1 COMPLETE.** Nothing Phone 1 (Android 15) paired first-try with the final flow, inputs correct, own "Wireless Controller" name; latency recorded (avg 7.85 ms within the <10 ms budget, p95 23.93 ms flagged for Step 2); Steam lists both phones as "Sony Computer Entertainment Wireless Controller", its wizard ran with PlayStation-style prompts. All 6 ROADMAP M1 criteria ticked; Step 1 → DONE. Next: Step 2 (DS4 hardening) |

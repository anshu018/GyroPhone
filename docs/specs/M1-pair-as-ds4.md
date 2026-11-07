# M1 spec — phone pairs as a DS4 ("Hello, gamepad")

Milestone: [M1](../ROADMAP.md#m1--hello-gamepad-phone-pairs-as-a-ds4--not-started) · Ver-1 Step 1 · Written 2026-11-07, approved by the user the same day. This file is the source of truth for M1; code implements it.

## Goal

Prove the kill-switch assumption behind [ADR-001](../DECISIONS.md): an Android phone can register as a DualShock 4-shaped HID device over Bluetooth, a PC pairs to it with zero PC-side software, and buttons and sticks move in a Windows gamepad tester — on two real devices. This is the spike that decides whether the plan holds; everything downstream (gyro, haptics, layouts) is built on this transport. Code quality is spike-quality by design: correct structure and logging, deliberately minimal UI.

## Requirements

### R1 — Project scaffold (Ver-1 Step 0)

- `flutter create app --org com.gyrophone --project-name gyrophone`.
- `applicationId` is **`com.gyrophone.app`** — the create command yields `com.gyrophone.gyrophone`, so the id is edited in `android/app/build.gradle` after scaffolding (the Kotlin `namespace` stays `com.gyrophone.gyrophone`; only the application id matters externally). Recorded as a pitfall.
- `minSdk` **28** in `android/app/build.gradle` — the `BluetoothHidDevice` floor. Never the default.
- `flutter_lints` enabled (template default), zero findings.
- `.gitattributes` at repo root: `* text=auto eol=lf` (ends the CRLF warnings).
- Gradle/JDK: system Java is 22. If Gradle objects, pin `org.gradle.java.home` for this project only. Never change the system JDK.

### R2 — Permissions and HID registration (`HidPlugin.kt`)

- Manifest: `BLUETOOTH_CONNECT` (API 31+), plus legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` with `android:maxSdkVersion="30"`. No location permission (the app never scans). No `VIBRATE` until M3.
- `BLUETOOTH_CONNECT` is requested at runtime **and granted** before `registerApp` — registration fails silently otherwise on Android 12+.
- Get the profile proxy via `BluetoothAdapter.getProfileProxy(context, listener, BluetoothProfile.HID_DEVICE)`.
- `registerApp(sdp, null, null, executor, callback)` where `executor` is a dedicated single-thread executor — no Bluetooth work on the UI thread, ever.
- The boolean returned by `registerApp`/`connect`/`sendReport` means "command sent", not "succeeded". Registration truth is `Callback.onAppStatusChanged`; connection truth is `Callback.onConnectionStateChanged`.
- The OS auto-unregisters the app when it is not foreground (`onAppStatusChanged` fires unsolicited, e.g. BT toggled off). The state machine observes this and re-registers on resume.

### R3 — SDP record (byte-faithful to the DS4's own record)

From the dumped DS4 SDP response ([References](#references)):

| Field | Value |
|-------|-------|
| Service name | `Wireless Controller` |
| Service description | `Game Controller` |
| Provider | `Sony Computer Entertainment` |
| HID subclass (attr 0x0202) | **`0x08`** — the DS4's actual byte, not Android's `SUBCLASS2_GAMEPAD` (`0x02`) |
| Descriptors | the 356-byte Bluetooth report descriptor in [R4](#r4--report-descriptor-byte-exact) |

The phone's Class of Device stays "Phone" (apps cannot change it; prior art confirms hosts pair via the SDP record regardless). Do not chase CoD tricks.

### R4 — Report descriptor (byte-exact)

The DS4 **Bluetooth** report descriptor, 356 bytes, transcribed from the SDP dump of real hardware. This is the USB descriptor's sibling, not the USB descriptor itself (the USB one is 467 bytes and declares output `0x05`; the BT one declares input+output `0x11`). Transcribed verbatim into `Ds4Descriptors.kt` with the source in the comment; never edited by hand.

```
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
```

What it declares: a Generic Desktop / Game Pad application collection containing

- **Input report `0x01`** — the small report: X, Y, Z, Rz usages (4 × 8-bit, 0–255), hat switch (4-bit with null state), 14 buttons, 6-bit padding, Rx/Ry (2 × 8-bit = L2/R2 analog). 9-byte payload, 10 bytes with the report ID.
- Vendor-page features (calibration `0x02`/`0x05`, version `0xA3`/`0x06`, others `0x03`, `0x04`, `0x07`, `0x08`, `0xF0`–`0xF2`, `0x82`–`0x84`, `0x90`–`0x93`, `0xA0`, `0xA4`).
- Vendor page `0xFF00`, **input report `0x11` and output report `0x11`, 77-byte payloads each** (78 bytes with the report ID) — the full DS4 report.
- Audio report variants `0x12`–`0x19` (input+output, larger payloads).

Unit test asserts: length == 356, first bytes `05 01 09 05`, last bytes `B1 02 C0`, anchor byte runs. The real gate is the device test (byte-faithfulness rule).

### R5 — Input reports (M1 sends `0x01`)

A real DS4 sends input report `0x01` **until the host reads feature `0x02`** (calibration), then switches to `0x11`. Windows' in-box HID stack never reads `0x02` and parses only the standard usages inside `0x01` — to it, `0x11` is vendor-opaque. Therefore M1 sends **`0x01`**; the calibration-triggered switch to `0x11` is Step 2 work, faithful to real-DS4 behavior.

Input report `0x01` layout (report ID passed to `sendReport` separately; `data` is the 9-byte payload):

| Offset | Content |
|--------|---------|
| 0 | Left stick X, unsigned, center 128 |
| 1 | Left stick Y, unsigned, center 128 |
| 2 | Right stick X, unsigned, center 128 |
| 3 | Right stick Y, unsigned, center 128 |
| 4 | bits 0–3: hat (0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=released); bits 4–7: Square, Cross, Circle, Triangle (1 = pressed) |
| 5 | bits 0–7: L1, R1, L2, R2, Share, Options, L3, R3 |
| 6 | bits 0–1: PS, touchpad-click; bits 2–7: counter (wraps) |
| 7 | L2 analog (0 = released) |
| 8 | R2 analog (0 = released) |

Send rules: on state change with identical-report dedupe, capped at 120 Hz, from a dedicated sender thread with a reused buffer (allocation-light from day one — the hot-loop invariant arrives with M2's sensor rate). A **neutral report is sent on focus loss** so Windows never holds a stuck button. Touch controls in M1: sticks driven by on-screen drags, buttons by on-screen touches (the status screen doubles as a crude input source — enough for a tester).

For reference (implemented in Step 2, not now) — the `0x11` payload map as verified against the raw DS4 capture (77 bytes after the report ID; motion values signed 16-bit little-endian): flags `0xC0` at 0, then sticks at 2–5, buttons at 6–8, L2/R2 at 9–10, timestamp at 11–12, gyro XYZ at 14–19, accel XYZ at 20–25, then touch/pad region. The exact battery byte (sources disagree: full byte at 13 vs nibble at 31) and timestamp semantics are pinned in Step 2 against DS4Windows/ds4drv. CRC-32 (polynomial `0x4C11DB7`) over the report is a Step 2 item.

### R6 — Host-request handling (log-first)

- `onGetReport` → `replyReport`: input `0x01` returns the current report padded to the requested bufferSize; feature `0x02` returns 36 zero bytes; anything else is logged. (Windows' in-box driver never asks; a Steam DS4 path would — logged evidence matters.)
- `onSetReport` / `onInterruptData` → log report ID + size only. Real consumption is Step 2 (`onInterruptData` is where BT output report `0x11` rumble arrives) and Step 5.
- `onSetProtocol` → assume report mode, log. `onVirtualCableUnplug` → state-machine transition (host dropped the pairing).

### R7 — Connection state machine (Dart `HidBridge`)

States: `uninitialized → unregistered → registering → registered → connected → streaming → error`. Transitions are logged with timestamps through the logger (never toasts; never report-byte logging — spam hides real signals). Handled cases:

- Bluetooth on/off (unsolicited `onAppStatusChanged(false)`).
- App backgrounded → OS auto-unregister → re-register on resume.
- Host-initiated pairing (the normal path: user pairs from Windows).
- App-initiated `connect(device)` for already-bonded hosts (handles "paired before, profile added after").
- Disconnect/reconnect without app restart.

Platform channel: MethodChannel (`register` / `unregister` / `connect` / `sendReport` / state queries) plus events Kotlin→Dart for state changes and host requests. Unit-tested against a fake channel.

### R8 — Temporary status screen

Minimal, per the [UIUX.md](../UIUX.md) interim rule — look is intentionally temporary, no design pass: connection state (loudest element), registered/host device name, and step-by-step PC pairing instructions. On-screen sticks/buttons double as the M1 input source. Landscape-locked from day one (UIUX fixed constraint: "no exceptions in v1").

### R9 — Measurements and evidence (recorded in this file, then RESEARCH.md)

- Input-path latency: instrument touch-event → `sendReport` complete; record avg/p95 against the <10 ms budget in [ARCHITECTURE.md](../ARCHITECTURE.md).
- OEM HID-device profile presence: `adb shell getprop bluetooth.profile.hid.device.enabled` on both devices.
- Windows Device Manager hardware IDs after pairing (VID/PID evidence — see Open questions).
- What Steam (running) lists under Settings → Controller for the paired device.

## Acceptance criteria

Mirrors [ROADMAP.md](../ROADMAP.md) M1; a box is ticked only after the criterion passes on hardware.

- [ ] M1 spec written and approved
- [ ] Phone registers as a DualShock 4; PC pairs from Bluetooth settings
- [ ] Buttons and sticks visible and responsive in a Windows gamepad tester
- [ ] Works on the user's device and at least one other (OEM quirk check)
- [ ] State machine survives disconnect/reconnect without app restart
- [ ] Input-path latency measured and recorded against the budget in ARCHITECTURE.md

## Task list

1. Write this spec + transport findings into [RESEARCH.md](../RESEARCH.md); commit.
2. Scaffold (R1): `flutter create`, applicationId/minSdk edits, `.gitattributes`, lints, doctor check; tick Ver-1 Step 0; commit.
3. `Ds4Descriptors.kt` (R3–R4) with integrity unit test.
4. `HidPlugin.kt` (R2, R6): permissions, proxy, `registerApp`, callbacks, method channel.
5. Dart `HidBridge` state machine (R7) + unit tests on a fake channel.
6. `ReportPacker` for input `0x01` (R5) + golden-byte unit tests.
7. Temporary status screen (R8) with landscape lock.
8. `flutter analyze` + `flutter test` green; install on the Nord 5 via USB debugging.
9. Device tests per R9 on Nord 5, then Nothing Phone 1; record latency + evidence.
10. Docs in the same change as the work they describe: [ARCHITECTURE.md](../ARCHITECTURE.md) corrections (BT output is `0x11`, callback names, report-mode note, VID/PID risk), Ver-1 Step 1 ticks, [STATUS.md](../../STATUS.md) session entry, ROADMAP ticks only for criteria that passed; commit and push.

## Pitfalls (do not)

Pre-filled from [Ver-1.md](../../Ver-1.md) and the 2026-11-07 research; appended in-session whenever a trap is discovered.

- Do not write or "improve" the descriptor from memory — transcribe from the pinned dump, assert 356 bytes, and expect one harmless `0x00` appended in transit (Linux dmesg logs "unknown main item tag 0x0"; prior-art-confirmed, benign).
- Do not request `BLUETOOTH_CONNECT` lazily — grant before `registerApp` or registration fails silently on Android 12+.
- Do not assume the report ID rides inside `data`: `sendReport(device, id, data)` takes the ID separately, and `onInterruptData`/`onSetReport` deliver it separately — prepending it twice corrupts every report (verified in AOSP JNI source).
- Do not pair before registering: hosts cache the SDP record at pair time. A phone already paired as a phone must be removed and re-paired. Any descriptor/SDP change requires re-pairing both ends.
- Do not treat `registerApp`'s boolean as success — track `onAppStatusChanged`; the OS auto-unregisters backgrounded apps and on BT off.
- Do not send `0x11` reports to Windows in M1 — its in-box stack parses only the standard usages of `0x01`; `0x11` reads as vendor-opaque bytes and the tester shows nothing.
- Do not pass Android's `SUBCLASS2_GAMEPAD` (0x02) — the DS4's own SDP record says subclass `0x08`.
- Do not run BT work on the UI thread; callbacks go to a dedicated executor; state transitions go to the logger, not toasts; report bytes are never logged.
- Do not "fix" Java 22 via the system JDK — pin per-project only.
- Do not rename the package after scaffolding — decide now (done: applicationId `com.gyrophone.app`, see R1).
- Do not commit `local.properties`, keystores, or `.gradle/` — root `.gitignore` covers them; verify before the first app commit.
- Do not test on an emulator — `BluetoothHidDevice` needs real Bluetooth hardware (Nord 5 primary, Nothing Phone 1 secondary).
- Do not chase the Class of Device — it stays "Phone" by platform design; the SDP record is what hosts read.
- Do not expect Steam to call this a DS4 — see Open questions; record what it says instead of fighting it in M1.

## Lessons learned

Filled in when the milestone closes: what actually happened, what the Pitfalls section missed, what the next agent must know.

## Open questions

1. **Steam classification (the big one).** A real DS4 advertises Sony VID/PID `054C:05C4` in a separate SDP Device-ID record; Android's public API does not let an app set that record, and Steam/SDL identifies DS4s by VID/PID. Expected outcome: Windows sees a working gamepad (M1 unaffected) while Steam labels it "Generic Gamepad" — which would block the M2 gyro and M3 rumble paths as currently designed. M1's device test measures this for free (R9 evidence). If confirmed, the architecture decision (possibly revisiting ADR-001's no-PC-software boundary) belongs to the user, made on data.
2. Windows pairing UX with a phone-CoD device advertising a gamepad SDP record (observed in R9).
3. Auto-unregister behavior specifics on OxygenOS 15 and Nothing OS (observed in R9).
4. Battery byte location/scale and timestamp semantics in report `0x11`; gyro axis order (`X,Y,Z` vs `X,Z,Y` — sources disagree) — pinned in Steps 2–3 against DS4Windows/ds4drv with the raw capture as cross-reference.

## References

All retrieved 2026-11-07. Facts and their confidence labels are recorded in [RESEARCH.md](../RESEARCH.md).

- [PSDevWiki — DS4-BT](https://www.psdevwiki.com/ps4/DS4-BT): the SDP response of a real DS4 (source of the 356-byte descriptor above; original paste from eleccelerator.com, 18 January 2014), report `0x11` layouts, CRC polynomial `0x4C11DB7`.
- [Controllers Fandom — DualShock 4 Data Structures](https://controllers.fandom.com/wiki/Sony_DualShock_4/Data_Structures): `0x11` input/output struct maps (battery nibble at +31, gyro order X,Z,Y — cross-checked).
- [GIMX wiki — DualShock 4](https://gimx.fr/wiki/index.php?title=DualShock_4): `0x01`-until-calibration-then-`0x11` behavior, BT output `0x11` rumble offsets, raw captures.
- [Linux kernel drivers/hid/hid-sony.c (v6.1)](https://raw.githubusercontent.com/torvalds/linux/v6.1/drivers/hid/hid-sony.c): `DS4_INPUT_REPORT_0x11_SIZE 78`, USB output `0x05` size 32, CRC-32 validation of BT reports.
- [Android — BluetoothHidDevice](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice) and [Callback](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice.Callback): API 28+, method semantics, foreground auto-unregister.
- [AOSP com_android_bluetooth_hid_device.cpp](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/android/app/jni/com_android_bluetooth_hid_device.cpp): report-ID handling in both directions.
- [blugaemand](https://github.com/pablopenna/blugaemand) (Android `registerApp` gamepad, prior art): register-before-pairing, SDP caching, DirectInput-not-XInput on Windows, CoD unchanged, OEM profile sysprop check, neutral-report-on-focus-loss.

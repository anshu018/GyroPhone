# Status

The living snapshot. Read this first, every session, human or agent. Update it at the end of every session and after every milestone (contract in [AGENTS.md](AGENTS.md)).

**Last updated:** 2026-11-11 (late)
**Current phase:** Phase 0 — **M2 code complete**; device tests remain
**Current goal:** device-test day for M2 (needs the user, ~45 min): pair, joy.cpl sweep, game binding, 10-min drift, latency recording
**Next action:** user plugs in the Nord 5 (USB) → run the device-test ladder in the M2 spec's task 8
**Blockers:** none in code; waiting on the user's device session

## Completed

- Research (2026-11-07): competitor map, market, open-source vetting, feasibility, economics — all sourced in [docs/RESEARCH.md](docs/RESEARCH.md)
- Twelve decisions locked in [docs/DECISIONS.md](docs/DECISIONS.md)
- Development environment ready (Flutter 3.47.9, Android SDK 36.1.0 + NDK 28.2, `flutter doctor` green)
- **M1 spec written and approved** (`docs/specs/M1-pair-as-ds4.md`, 2026-11-07)
- **Step 0 scaffold done** (2026-11-07): `app/` (applicationId `com.gyrophone.app`, minSdk 28, `.gitattributes`)
- **Step 1 spike implemented** (2026-11-07/08): Kotlin `HidPlugin.kt` + `Ds4Descriptors.kt`, Dart `HidBridge` + `Ds4ReportPacker` + status screen; staff-level review applied; 28 Dart tests + 7 Kotlin descriptor tests green
- **M1 device tests passed (2026-11-08) on both devices**:
  - Nord 5 (Android 16): after a debugging campaign that found five platform behaviors (all in the spec's Pitfalls), sticks+buttons correct in joy.cpl, latency avg 7.85 ms (budget <10 ms; p95 23.93 ms flagged for Step 2)
  - Nothing Phone 1 (Android 15): **first-try pairing** with the final flow (register → in-app discoverable → PC pairs → connected in 42 s), inputs correct, own "Wireless Controller" name
  - Steam lists both phones simultaneously as "Sony Computer Entertainment Wireless Controller"; its mapping wizard ran with PlayStation-style input names (L3) — definitive DS4-vs-generic classification is Step 2's first task
- Platform findings recorded in the spec's Pitfalls + [RESEARCH.md](docs/RESEARCH.md): stale bonds poison pairing; app must be foreground during pairing (in-app discoverable request); full 356-byte DS4 descriptor fails to install on this stack↔Windows pair (M1 uses the DS4's own 79-byte small-report descriptor — wire-faithful); subclass 0x08 exonerated; registration-slot conflicts; Windows name cache; adb quirks (logcat filtering, wireless-pairing VPN address)
- ROADMAP M1 fully ticked; Ver-1 Step 1 marked DONE
- **M2 spec written** (2026-11-11, `docs/specs/M2-wheel.md`): axis path via report `0x01` byte 0 (X usage, no descriptor change), native Kotlin sensor hot loop (user decision), full cockpit layout v1 (user decision), Ver-1 Step 2 closed as obsolete, `HIGH_SAMPLING_RATE_SENSORS` fact verified against the Android docs and recorded in RESEARCH.md. **APPROVED by the user 2026-11-11 — implementation started; ADR-012 recorded; ROADMAP M2 re-framed to the axis path in the same change.**

## In progress

- **M2 implementation, code complete (2026-11-11)**: native hot loop (`SensorFusion`/`WheelModel`/`Ds4InputPacker` + HidPlugin tick), wheel cockpit UI (schema/engine/wheel screen/pedals/sheets), bridge commands, HIGH_SAMPLING_RATE_SENSORS. Gates green: analyze 0 findings, 23/23 Dart, 38 Kotlin JVM (7 descriptor + 14 wheel-model + 10 fusion + 7 packer). Test-caught pre-device: gyro integration overshoot (÷rate fix), deadzone full-lock byte loss. Device tests pending (Ver-1 Steps 3–4 remain IN PROGRESS until they pass).

## Next, in order

1. **M2 device-test day (needs the user)**: Nord 5 over USB → install → pair from the PC (app foreground!) → joy.cpl steering-byte sweep (byte-faithfulness) → BeamNG/Assetto Corsa bind `X Axis` to steering + drive with pedals → 10-min drift check → record sensor-path latency → repeat the sensor sanity on the Nothing Phone 1. Capture per-game binding steps for the Step 9 guide.
2. Tick ROADMAP M2 criteria that pass; record latency/drift numbers in the M2 spec + RESEARCH.md; resolve the spec's open questions (RV vs GAME_ROTATION_VECTOR, quantization feel, X vs Rz axis).
3. Rumble (M3) decision deferred; its option menu no longer includes the full-descriptor disguise (declined by the user, see Open questions).

## Open questions

- ~~Steam classification~~ **ANSWERED 2026-11-08: Generic Gamepad** (evidence chain in [spec open question 1](docs/specs/M1-pair-as-ds4.md)). Consequence limited to the extras — the M2 wheel works via the axis path regardless (see Next item 1).
- **Full-descriptor retry experiment: DECLINED by the user (2026-11-08)** — will not be attempted. The 79-byte small descriptor is the shipping approach; why the full descriptor failed to install on this stack↔Windows pair stays an open mystery we are not spending time on. Consequence: Steam-Input gyro and M3 rumble must use non-disguise routes (DSU-style protocols for supporting games, or a revised ADR-001 with a PC-side component) — decided when M3 nears.

## Gotchas for next session

- **All M2 spec decisions live in the spec** — read `docs/specs/M2-wheel.md` before any M2 code. The two user decisions of 2026-11-11: the sensor hot loop is native Kotlin (report ownership moves off Dart), and wheel layout v1 is the full cockpit (pedals included). `HIGH_SAMPLING_RATE_SENSORS` goes in the manifest from the first M2 build (Android 12+ rate-limits/throws otherwise — see RESEARCH.md platform constraints).
- **All M1 pairing pitfalls live in [the spec's Pitfalls](docs/specs/M1-pair-as-ds4.md) — read them before touching Bluetooth code.** The big three: stale bonds poison pairing (remove both ends, re-pair); the registered app must be foreground during pairing (in-app "Make discoverable" handles it); the 79-byte small descriptor is the shipping artifact (the full 356-byte one is kept byte-exact as reference only).
- Only one app can hold the HID registration per phone; force-stop doesn't reliably release it — toggle Bluetooth to clear (`adb shell svc bluetooth disable/enable`).
- `adb logcat` tag filtering flakes on this machine; use `adb shell "logcat -d | grep …"`. The Nord 5 works over USB adb; the Nothing Phone 1 works over **wireless** adb (paired; its dialog shows the VPN IP when its VPN is on — use `adb mdns services` for the real address).
- Latency display: `n=` pins at 128 once the rolling window is full — by design.
- `mklink` unavailable on this machine (no admin) — no CLAUDE.md, by user decision
- New terminals pick up Flutter via the updated user PATH; the current session may need `export PATH="/c/Users/ash74/dev/flutter/bin:$PATH"`
- Java 22 works with the project's Gradle (verified by build); no JDK pinning needed
- An emulator cannot replace real phones — `BluetoothHidDevice` needs real Bluetooth hardware
- Git CRLF is normalized by `.gitattributes`; occasional warnings are expected and harmless
- Docs set is closed — new files require a user decision (ADR-008/009 record the system)

## Environment

- Machine: Windows 11 (26H2), Git Bash; repo at `C:\Users\ash74\GyroPad`, git branch `main`, remote `origin` = github.com/anshu018/GyroPhone (private)
- Flutter 3.47.9 stable: `C:\Users\ash74\dev\flutter` (user PATH); Dart 3.13.7; Android SDK 36.1.0 (+ NDK 28.2.13676358); system Java 22 (works, unpinned)
- PC Bluetooth: present and working; both phones paired to it as HID devices
- Test devices: OnePlus Nord 5 (primary — USB adb; transport proven), Nothing Phone 1 (secondary — wireless adb at 10.95.76.195:42835, may change; transport proven)

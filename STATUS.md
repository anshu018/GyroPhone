# Status

The living snapshot. Read this first, every session, human or agent. Update it at the end of every session and after every milestone (contract in [AGENTS.md](AGENTS.md)).

**Last updated:** 2026-11-08
**Current phase:** Phase 0 — M1 device test: **transport proven on the primary device**
**Current goal:** M1 close-out (latency numbers, Steam classification verdict, second device)
**Next action:** read out the app's latency stats, click through Steam's controller entry for the DS4-vs-generic verdict, then the Nothing Phone 1 test
**Blockers:** none

## Completed

- Research (2026-11-07): competitor map, market, open-source vetting, feasibility, economics — all sourced in [docs/RESEARCH.md](docs/RESEARCH.md)
- Twelve decisions locked in [docs/DECISIONS.md](docs/DECISIONS.md)
- Complete documentation set + persona ([ADR-008](docs/DECISIONS.md), [ADR-009](docs/DECISIONS.md))
- Development environment ready (Flutter 3.47.9, Android SDK 36.1.0, `flutter doctor` green); NDK 28.2.13676358 installed (needed by the Android build, 2026-11-08)
- **M1 spec written and approved** (`docs/specs/M1-pair-as-ds4.md`, 2026-11-07)
- **Step 0 scaffold done**: `app/` (applicationId `com.gyrophone.app`, minSdk 28, `.gitattributes`), analyze/test green (2026-11-07)
- **Step 1 spike implemented and device-tested (2026-11-08)**: Kotlin `HidPlugin.kt` + `Ds4Descriptors.kt`, Dart `HidBridge` state machine + `Ds4ReportPacker`, status screen; staff-level review pass applied; 28 Dart tests + 7 Kotlin descriptor tests green; APK builds
- **Transport proven on the Nord 5 (2026-11-08)**: phone pairs as a DS4 from Windows Bluetooth settings, stays connected, sticks **and** buttons map correctly in `joy.cpl`, Steam lists "Sony Computer Entertainment Wireless Controller". Device-initiated reconnect, background auto-unregister/re-register, and BT-toggle recovery all demonstrated live.
- Platform findings recorded (see the spec's Pitfalls + RESEARCH.md): stale bonds poison pairing; app must be foreground during pairing (in-app discoverable request implemented); the full 356-byte DS4 descriptor fails to install on this stack↔Windows pair (M1 registers the DS4's own 79-byte small-report descriptor instead — wire-faithful for M1); subclass 0x08 exonerated; Windows caches device names across re-pairs (cosmetic)

## In progress

- M1 acceptance close-out: latency readout (instrumented, numbers pending), Steam classification verdict (entry visible; DS4-vs-generic pending the click-through), Nothing Phone 1 second-device test

## Next, in order

1. Record the latency numbers in the spec (R9) and tick the ROADMAP criterion
2. Steam → Controller → click the entry: record DS4 vs Generic verdict — feeds the M2 gyro decision ([spec open question 1](docs/specs/M1-pair-as-ds4.md)) — wizard already ran with PlayStation-style input names (L3), full classification verdict pending
3. Nothing Phone 1: install, pair, joy.cpl (OEM quirk check)
4. Spec task 10: phone-side connect UI for bonded hosts (user-approved; bridge support already exists)
5. Tick remaining ROADMAP M1 criteria; M1 exit → Ver-1 Step 2 (DS4 hardening)

## Open questions

- Steam classification of a non-Sony-DID device (evidence being captured — see spec open question 1; the M2 architecture decision is the user's if Steam says "Generic")
- Whether the full-DS4-descriptor install failure is OxygenOS-16-specific or Windows-26H2-wide (Nothing Phone 1 test isolates it)

## Gotchas for next session

- **All M1 pairing pitfalls live in [the spec's Pitfalls](docs/specs/M1-pair-as-ds4.md) — read them before touching Bluetooth code.** The big three: stale bonds poison pairing (remove both ends, re-pair); the registered app must be foreground during pairing (in-app "Make discoverable" handles it); the full DS4 descriptor is registered for Step 2 only — M1 uses the small one.
- Only one app can hold the HID registration; force-stop doesn't reliably release it — toggle Bluetooth to clear (`adb shell svc bluetooth disable/enable`).
- `adb logcat` tag filtering flakes on this machine; use `adb shell "logcat -d | grep …"`.
- `mklink` unavailable on this machine (no admin) — no CLAUDE.md, by user decision
- New terminals pick up Flutter via the updated user PATH; the current session may need `export PATH="/c/Users/ash74/dev/flutter/bin:$PATH"`
- Java 22 works with the project's Gradle (verified by build); no JDK pinning needed
- An emulator cannot replace a real phone for M1 — `BluetoothHidDevice` needs real Bluetooth hardware
- Git CRLF is normalized by `.gitattributes`; occasional warnings are expected and harmless
- Docs set is closed — new files require a user decision (ADR-008/009 record the system)

## Environment

- Machine: Windows 11 (26H2), Git Bash; repo at `C:\Users\ash74\GyroPad`, git branch `main`, remote `origin` = github.com/anshu018/GyroPhone (private)
- Flutter 3.47.9 stable: `C:\Users\ash74\dev\flutter` (user PATH); Dart 3.13.7; Android SDK 36.1.0 (+ NDK 28.2.13676358); system Java 22 (works, unpinned)
- PC Bluetooth: present and working
- Test devices: OnePlus Nord 5 (primary — USB debugging enabled, app installed, transport proven), Nothing Phone 1 (secondary — pending)

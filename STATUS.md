# Status

The living snapshot. Read this first, every session, human or agent. Update it at the end of every session and after every milestone (contract in [AGENTS.md](AGENTS.md)).

**Last updated:** 2026-11-08 (late)
**Current phase:** Phase 0 — **M1 complete** (all six acceptance criteria passed on two devices)
**Current goal:** none in flight — M1 closed
**Next action:** Ver-1 Step 2 (DS4 hardening): write its spec additions, first task = Steam click-through verdict (DS4 vs generic)
**Blockers:** none

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

## In progress

- Nothing.

## Next, in order

1. **Ver-1 Step 2 (DS4 hardening)**: write its spec — **opening with the M2 gyro architecture decision**: Steam classifies the device as Generic (answered, see spec open question 1), so the original "Steam sees DS4 gyro" path needs either the full-descriptor retry experiment, a DSU/cemuhook route, or a revised ADR-001 — the user decides on evidence
2. Phone-side connect UI for bonded hosts (spec task 11, user-approved)
3. Then Steps 3+ per [Ver-1.md](Ver-1.md); milestone acceptance criteria in [docs/ROADMAP.md](docs/ROADMAP.md) remain the definition of done

## Open questions

- ~~Steam classification~~ **ANSWERED 2026-11-08: Generic Gamepad** (evidence chain in [spec open question 1](docs/specs/M1-pair-as-ds4.md)). M2 gyro path decision is now the user's.
- Whether the full-DS4-descriptor install failure is OxygenOS-16-specific or Windows-26H2-wide (Nothing Phone 1 also runs the small descriptor — a full-descriptor retry on it is a cheap Step 2 experiment)

## Gotchas for next session

- **All M1 pairing pitfalls live in [the spec's Pitfalls](docs/specs/M1-pair-as-ds4.md) — read them before touching Bluetooth code.** The big three: stale bonds poison pairing (remove both ends, re-pair); the registered app must be foreground during pairing (in-app "Make discoverable" handles it); the full DS4 descriptor is registered for Step 2 only — M1 uses the small one.
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

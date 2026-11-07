# Status

The living snapshot. Read this first, every session, human or agent. Update it at the end of every session and after every milestone (contract in [AGENTS.md](AGENTS.md)).

**Last updated:** 2026-11-07
**Current phase:** Phase 0 — GyroPad MVP (environment ready, repo connected, code not started)
**Current goal:** none in flight — awaiting user's go to write the M1 spec
**Next action:** write `docs/specs/M1-pair-as-ds4.md`, get user approval, then scaffold the app in `app/`
**Blockers:** none

## Completed

- Research (2026-11-07): competitor map, market, open-source vetting, feasibility, economics — all sourced in [docs/RESEARCH.md](docs/RESEARCH.md)
- Ten decisions locked in [docs/DECISIONS.md](docs/DECISIONS.md) (incl. Bluetooth HID transport, stack, sequence, OpenBot base, documentation system, agent persona, provisional brand)
- Complete documentation set — 11 files, written file-by-file, style per [CONVENTIONS.md](CONVENTIONS.md); persona in [PERSONA.md](PERSONA.md) ([ADR-009](docs/DECISIONS.md))
- **Development environment set up (2026-11-07):** Flutter 3.47.9 stable installed at `C:\Users\ash74\dev\flutter` (in user PATH); Android cmdline-tools installed into the existing SDK (36.1.0); licenses accepted; `flutter doctor` fully green
- **GitHub repo connected (2026-11-07):** private repo [github.com/anshu018/GyroPhone](https://github.com/anshu018/GyroPhone), branch `main`, `.gitignore` in place (secrets patterns per CONVENTIONS never-do #3), initial commit pushed
- Test devices identified: primary **OnePlus Nord 5** (OxygenOS 15 / Android 15), secondary **Nothing Phone 1** (Android 13+) — both satisfy the Android 9 (API 28)+ requirement for `BluetoothHidDevice`; exact builds verified on-device during M1
- PC Bluetooth adapter confirmed present and working (paired devices enumerated)

## In progress

- Nothing.

## Next, in order

1. Write the M1 spec (`docs/specs/M1-pair-as-ds4.md`): goal, requirements, acceptance criteria, task list — get user approval
2. Scaffold the Flutter app in `app/` (`flutter create --org` …), add `.gitattributes` (LF policy), wire the Kotlin plugin skeleton
3. Implement M1 per spec ([docs/ROADMAP.md](docs/ROADMAP.md) for scope and acceptance criteria)

## Open questions

- None blocking.

## Gotchas for next session

- Full UI/UX design pass is deliberately deferred until before M2 UI work; only M1's temporary status screen is allowed until then ([docs/UIUX.md](docs/UIUX.md) interim rule)
- `mklink` unavailable on this machine (no admin) — no CLAUDE.md, by user decision
- New terminals pick up Flutter via the updated user PATH; the current session may need `export PATH="/c/Users/ash74/dev/flutter/bin:$PATH"`
- Java 22 is the system JDK; if Gradle complains at first Android build, pin the JDK for the project rather than changing the system Java
- An emulator cannot replace a real phone for M1 — `BluetoothHidDevice` needs real Bluetooth hardware; use the Nord 5 (primary) and the Nothing Phone 1 (secondary, OEM-quirk check)
- Git emitted LF→CRLF warnings on first commit (Windows autocrlf) — add a `.gitattributes` (`* text=auto eol=lf`) with the scaffold commit to normalize line endings
- Docs set is closed at 11 files — new files require a user decision (ADR-008/009 record the system)

## Environment

- Machine: Windows 11 (26H2), Git Bash; repo at `C:\Users\ash74\GyroPad`, git branch `main`, remote `origin` = github.com/anshu018/GyroPhone (private)
- Flutter 3.47.9 stable: `C:\Users\ash74\dev\flutter` (user PATH); Dart 3.13.7
- Android SDK 36.1.0: `C:\Users\ash74\AppData\Local\Android\Sdk` (cmdline-tools installed); system Java 22.0.2
- PC Bluetooth: present and working
- Target devices: OnePlus Nord 5 (primary), Nothing Phone 1 (secondary) — enable USB debugging when M1 starts

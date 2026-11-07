# Status

The living snapshot. Read this first, every session, human or agent. Update it at the end of every session and after every milestone (contract in [AGENTS.md](AGENTS.md)).

**Last updated:** 2026-11-07
**Current phase:** Phase 0 — GyroPad MVP (environment ready, code not started)
**Current goal:** connect the GitHub repo (user is creating it, name: GyroPhone), then write the M1 spec
**Next action:** user creates a private GitHub repo (GyroPhone) and shares the URL; then `git init` + first commit + push
**Blockers:** none — awaiting the repo URL

## Completed

- Research (2026-11-07): competitor map, market, open-source vetting, feasibility, economics — all sourced in [docs/RESEARCH.md](docs/RESEARCH.md)
- Nine decisions locked in [docs/DECISIONS.md](docs/DECISIONS.md) (incl. Bluetooth HID transport, stack, sequence, OpenBot base, documentation system, agent persona)
- Complete documentation set — 11 files, written file-by-file, style per [CONVENTIONS.md](CONVENTIONS.md); persona in [PERSONA.md](PERSONA.md) ([ADR-009](docs/DECISIONS.md))
- **Development environment set up (2026-11-07):** Flutter 3.47.9 stable installed at `C:\Users\ash74\dev\flutter` (in user PATH); Android cmdline-tools installed into the existing SDK (36.1.0) at `C:\Users\ash74\AppData\Local\Android\Sdk`; licenses accepted; `flutter doctor` fully green
- Test devices identified: primary **OnePlus Nord 5** (OxygenOS 15 / Android 15), secondary **Nothing Phone 1** (Android 13+) — both satisfy the Android 9 (API 28)+ requirement for `BluetoothHidDevice`; exact builds verified on-device during M1
- PC Bluetooth adapter confirmed present and working (paired devices enumerated)

## In progress

- Nothing.

## Next, in order

1. User creates a **private** GitHub repo (`GyroPad`) and shares the URL
2. Agent: `git init` in `C:\Users\ash74\GyroPad`, write `.gitignore`, first commit, add remote, push — user completes the one-time browser sign-in when Git Credential Manager opens
3. Write the M1 spec (`docs/specs/M1-pair-as-ds4.md`): goal, requirements, acceptance criteria, task list — get user approval
4. Scaffold the Flutter app in `app/`; implement M1 per spec ([docs/ROADMAP.md](docs/ROADMAP.md))

## Open questions

- Which hosting the user chooses for the private repo (GitHub assumed) — pending user creation

## Gotchas for next session

- Full UI/UX design pass is deliberately deferred until before M2 UI work; only M1's temporary status screen is allowed until then ([docs/UIUX.md](docs/UIUX.md) interim rule)
- `mklink` unavailable on this machine (no admin) — no CLAUDE.md, by user decision
- New terminals pick up Flutter via the updated user PATH; the current session may need `export PATH="/c/Users/ash74/dev/flutter/bin:$PATH"`
- Java 22 is the system JDK; if Gradle complains at first Android build, pin the JDK for the project rather than changing the system Java
- An emulator cannot replace a real phone for M1 — `BluetoothHidDevice` needs real Bluetooth hardware; use the Nord 5 (primary) and the Nothing Phone 1 (secondary, OEM-quirk check)
- Docs set is closed at 11 files — new files require a user decision (ADR-008/009 record the system)

## Environment

- Machine: Windows 11 (26H2), Git Bash; repo at `C:\Users\ash74\GyroPad` (not yet under git)
- Flutter 3.47.9 stable: `C:\Users\ash74\dev\flutter` (user PATH); Dart 3.13.7
- Android SDK 36.1.0: `C:\Users\ash74\AppData\Local\Android\Sdk` (cmdline-tools installed); system Java 22.0.2
- PC Bluetooth: present and working
- Target devices: OnePlus Nord 5 (primary), Nothing Phone 1 (secondary) — both USB-debuggable when M1 starts

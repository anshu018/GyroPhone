# Conventions

The rules for anyone writing code or documentation in this repo. The goal is predictability: any change should look like it came from the same careful team. Rationale lives in the referenced documents; this file states the rules.

## Precedence when rules conflict

1. The user's direct instruction in the conversation
2. [AGENTS.md](AGENTS.md) (the agent contract)
3. This file
4. Other documents in `docs/`

If precedence does not resolve a conflict, stop and ask the user. Do not guess.

## Code style

- **Dart/Flutter:** follow [Effective Dart](https://dart.dev/effective-dart); `dart format` on everything; `flutter analyze` reports zero findings before anything is called done.
- **Kotlin (platform channels):** default IntelliJ style; `ktlint` once added. `HidPlugin.kt` is the most safety-critical file in the repo — changes there are deliberate, small, and device-tested.
- **Comments** explain *why*, not *what*, in English, matching surrounding density. No commented-out code left behind.
- **No bare `print`/`debugPrint` in committed code** — use the logger. HID state-machine transitions are always logged; report bytes are not (log spam hides real signals).
- **No silent catches.** Every `catch` either handles the condition or rethrows with context. Swallowed errors in the HID path produce exactly the kind of bug that takes days to find on a real device.

## Folder structure

```
app/
  lib/
    main.dart
    sensors/        sensor fusion + 900° wheel model
    hid/            platform-channel bridge (Dart side)
    haptics/        waveform engine
    layouts/        wheel, gamepad, settings, connection screens
  android/app/src/main/kotlin/.../HidPlugin.kt   DS4 emulation core
firmware/           (Phase 1+) ESP32, OpenBot-derived
docs/               VISION, RESEARCH, ARCHITECTURE, ROADMAP, DECISIONS, UIUX, specs/
```

Module boundaries come from [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — a bug in steering feel should land in exactly one module. New top-level folders need user approval and a note in [docs/DECISIONS.md](docs/DECISIONS.md). Renaming a public API updates the specs and docs in the same change.

## Dependencies

Every new package must clear three checks, stated in the commit message:

1. **Justification** — what it does that we would otherwise write, and why that trade is right.
2. **License** — MIT, Apache-2.0, or BSD only. Copyleft (GPL, AGPL, LGPL) may not link into proprietary components ([ADR-007](docs/DECISIONS.md)).
3. **Maintenance** — a recent release or commit history. The ViGEmBus retirement is the standing lesson: dependencies can die under a working product.

## Testing

Gate: `cd app && flutter analyze && flutter test` passes before any milestone is called done.

| What | How |
|------|-----|
| Sensor fusion math, wheel model (range, clamp, curve, deadzone) | unit tests |
| Report packing/parsing (byte-level), descriptor changes | unit tests + **device test** |
| `HapticEngine` pattern selection | unit tests |
| `HidBridge` state-machine transitions | unit tests |
| Pairing, gamepad-tester visibility, Steam gyro, rumble replay | device test, logged in [STATUS.md](STATUS.md) |

HID changes are not done until a real PC sees them. If a bug reaches a real device, the fix lands with the unit test that would have caught it. UI widget tests wait until M3 unless a layout contains logic.

## Commits and history

- Conventional commits: `feat:`, `fix:`, `spike:`, `docs:`, `chore:`. One logical change per commit. `spike:` marks throwaway exploration that proves or disproves something.
- Work lands on `main` in small steps; no force-pushes to `main`.
- Every change carries its documentation updates in the same commit ([AGENTS.md](AGENTS.md) contract).
- `CHANGELOG.md` starts at v0.1.0, Keep-a-Changelog categories (Added / Changed / Deprecated / Removed / Fixed / Security). Until then, commit history is the log.

## Documentation style

Bases: [Google developer docs style](https://google.github.io/styleguide/docguide/best_practices.html), [Diátaxis](https://diataxis.fr/), [agents.md](https://agents.md).

**Voice:** short sentences, active voice, present tense. "Say what you mean, simply and directly." No marketing adjectives inside docs.

**Structure:** every file has exactly one job (tutorial / how-to / reference / explanation — never blended). One H1. Heading levels never skip. Headings are descriptive — the outline alone must tell the story.

**Formatting:** one blank line between all elements. Tables only for genuinely tabular data; lists for sequences. Code blocks carry a language tag. Links use descriptive text, never bare URLs. No decorative horizontal rules.

**Hygiene:** docs update in the same change as the code they describe. Outdated content gets cut, not annotated — maintain docs like a bonsai tree. Factual claims about the outside world carry a source link ([RESEARCH.md](docs/RESEARCH.md) is strictest about this).

## The never-do list

Binding on every human and agent. Violations are reverted, not discussed.

1. **No PC-side drivers, ever** — Bluetooth HID is the only PC transport ([ADR-001](docs/DECISIONS.md)).
2. **No iOS work in Phase 0** ([ADR-005](docs/DECISIONS.md)).
3. **Never create, edit, or commit secrets** — `.env`, keystores, API keys, pairing credentials. Local untracked files only, `.gitignore` correct before the first commit.
4. **Never delete files, folders, or git history** without explicit user confirmation in the conversation.
5. **Never add a dependency** without the three checks above (justification, license, maintenance).
6. **Never vendor OpenBot code** without license headers, and only under `firmware/` ([ADR-004](docs/DECISIONS.md)).
7. **Never edit an accepted ADR** — supersede it with a new numbered entry.
8. **Never expand scope unilaterally** — the non-goals in [docs/VISION.md](docs/VISION.md) are binding; propose, get approval, then record an ADR. Agents: adding features is not helpfulness, it is scope creep.
9. **Never claim work that did not happen** — a milestone is done only when its acceptance criteria pass, and a device test is reported only if one actually ran.

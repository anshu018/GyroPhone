# AGENTS.md

Instructions for AI agents working in this repo (and future human collaborators). Short by design: the rules live in the files this hub points to. Start with [STATUS.md](STATUS.md), then read this file top to bottom.

## The project in 30 seconds

GyroPad turns a phone into a cockpit controller. Tier 1 (current): an Android app that emulates a DualShock 4 over Bluetooth HID — 900° gyro steering wheel, gamepad, and rumble replay for PC games, with nothing installed on the PC. Tiers 2–3 (later): an ESP32 retrofit board for any RC car, then our own FPV camera car on OpenBot. Stack: Flutter UI, Kotlin platform channel for HID and haptics. The why is in [docs/VISION.md](docs/VISION.md); the how is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Read order for a new session

1. [STATUS.md](STATUS.md) — where we are: current goal, done, next, blockers, gotchas
2. [PERSONA.md](PERSONA.md) — who you are while you work: the standard of thinking, code, tests, and research
3. The current milestone spec in `docs/specs/` — the task, if one exists
4. [Ver-1.md](Ver-1.md) — the V1 execution plan: your step's full detail, tasks, and pitfalls
5. [docs/ROADMAP.md](docs/ROADMAP.md) — milestone scope, acceptance criteria, out-of-scope lists
6. [CONVENTIONS.md](CONVENTIONS.md) — code rules and the never-do list (**binding**)
7. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — modules, contracts, invariants, performance budgets
8. [docs/DECISIONS.md](docs/DECISIONS.md) — why things are the way they are (immutable log)
9. [docs/UIUX.md](docs/UIUX.md) — only for UI work (design pass pending; interim rules apply)
10. [docs/RESEARCH.md](docs/RESEARCH.md) — when a claim needs a source or a fact needs checking

## Session protocol

**Start:** read STATUS.md; load the current milestone spec; if STATUS is stale, ambiguous, or missing, confirm the task with the user — never infer it.

**End:** update STATUS.md (current goal, done, next, blockers, gotchas); tick [ROADMAP.md](docs/ROADMAP.md) checkboxes only for acceptance criteria that actually passed; leave the repo in a working state — `flutter analyze` and `flutter test` green, or the breakage plainly noted in STATUS.md.

## Working rules

- **Spec before code.** Code implements the approved milestone spec; the spec is the source of truth.
- **One milestone at a time; riskiest unknown first within it.**
- **Small working increments.** The app stays runnable after every change.
- **Documentation contract** — every event below requires its action in the same change:

| Event | Action |
|-------|--------|
| Session end **or** milestone completed | Update [STATUS.md](STATUS.md) |
| A V1 step starts, progresses, or completes | Update its status + checkboxes in [Ver-1.md](Ver-1.md) in the same change |
| A mistake or trap discovered while working | Record it **in the same session** in the current spec's *Pitfalls* section ([docs/specs/](docs/specs/README.md)); generalizable rules escalate to [CONVENTIONS.md](CONVENTIONS.md) → never-do list |
| Writing or rewriting any doc | Follow *Documentation style* in [CONVENTIONS.md](CONVENTIONS.md) |
| Architecture, library, or platform choice | New numbered ADR in [docs/DECISIONS.md](docs/DECISIONS.md) — never edit an accepted one |
| New competitor, market, or tech fact | [docs/RESEARCH.md](docs/RESEARCH.md), with source link and date |
| Acceptance criterion passes | Tick it in [docs/ROADMAP.md](docs/ROADMAP.md); one line in README status log at phase close |
| Behavior or interface change | Update [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) diagrams, components, invariants |

## Communication rules

- Report outcomes faithfully: a failed test is reported as failed, with the output. Never claim a device test that did not run ([CONVENTIONS.md](CONVENTIONS.md) never-do list, item 9).
- Surface disagreements with reasoning **before** complying silently — that is what a partner does; a wrong plan executed perfectly is still wrong.
- When a decision belongs to the user (scope, design, sequencing, money), ask. Guessing is never cheaper.

## Commands

```bash
cd app && flutter analyze && flutter test                  # Dart gate (CONVENTIONS.md)
cd app/android && ./gradlew testDebugUnitTest              # Kotlin JVM tests (descriptor integrity)
cd app && flutter run                                      # user's Android device via USB debugging
```

## Hard rules

The full list is [CONVENTIONS.md](CONVENTIONS.md) → *The never-do list*, and it is binding. The three most consequential: **no PC-side drivers, ever** ([ADR-001](docs/DECISIONS.md)); **no iOS work in Phase 0** ([ADR-005](docs/DECISIONS.md)); **never expand scope unilaterally** — non-goals in [docs/VISION.md](docs/VISION.md) are law, and adding features without approval is scope creep, not helpfulness.

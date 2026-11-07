# GyroPhone

One app, one brand, three products: your phone becomes the cockpit — first for PC games, then for real cars.

> **Naming note:** GyroPhone is the provisional working brand ([ADR-010](docs/DECISIONS.md)). "GyroPad" remains the internal codename for this repository and local folder until a final brand decision.

## The project in two minutes

GyroPad turns the phone you already own into a cockpit controller: a 900° gyro steering wheel with real haptic feedback. It ships in three steps:

| Step | Product | What it is |
|------|---------|------------|
| 1 | GyroPad app (current) | Android app: gyro wheel + gamepad + rumble for PC games over Bluetooth HID. Nothing installed on the PC. |
| 2 | Retrofit board | ESP32 + camera board wired into any RC car's servo and ESC leads; the phone replaces the stock controller. |
| 3 | FPV car | Our own car, camera at the driver's seat, paired to the app by code. |

Four pillars define the product: a true-haptic cockpit, driver-seat camera with head-look, an AI rival car, and the retrofit-any-car board.

Current status in one line: **documentation complete; Phase 0 / milestone M1 ("phone pairs as a DS4") is the next action.**

## Where to read what

| File | Read it when | It contains |
|------|--------------|-------------|
| [STATUS.md](STATUS.md) | **First, every session** | Living snapshot: current goal, done, next, blockers, gotchas |
| [AGENTS.md](AGENTS.md) | You are an AI agent or new contributor | Session protocol, working rules, documentation contract |
| [PERSONA.md](PERSONA.md) | You are the agent or engineer | The craft standard: how to think, write code and tests, research online, escalate |
| [CONVENTIONS.md](CONVENTIONS.md) | You write code or docs | Code style, testing, commits, the never-do list |
| [docs/VISION.md](docs/VISION.md) | You want the why | Product thesis, audiences, pillars, non-goals, success criteria |
| [docs/RESEARCH.md](docs/RESEARCH.md) | You need facts | Dated, sourced competitor map, market, open-source vetting, feasibility |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | You build or review | Modules, contracts, data flows, invariants, performance budgets |
| [docs/ROADMAP.md](docs/ROADMAP.md) | You plan or execute | Milestones M1–M3, phases 1–4, acceptance criteria |
| [docs/DECISIONS.md](docs/DECISIONS.md) | You ask "why X?" | Eight immutable decision records |
| [docs/UIUX.md](docs/UIUX.md) | You work on the UI | Fixed constraints and open design decisions (design pass pending) |
| [docs/specs/](docs/specs/README.md) | You start a milestone | One spec per milestone, written before code |

AI agents: [AGENTS.md](AGENTS.md) is your entry point after STATUS.md.

## Repository layout

```
GyroPad/
├── README.md            this file — the map
├── STATUS.md            living status snapshot (updated every session)
├── AGENTS.md            agent entry point and session protocol
├── PERSONA.md           the engineer's craft standard (thinking, code, tests, research)
├── CONVENTIONS.md       code rules and the never-do list
├── docs/
│   ├── VISION.md        product thesis and non-goals
│   ├── RESEARCH.md      sourced research dossier
│   ├── ARCHITECTURE.md  system design and invariants
│   ├── ROADMAP.md       milestones and acceptance criteria
│   ├── DECISIONS.md     immutable decision log
│   ├── UIUX.md          design constraints (full design pass pending)
│   └── specs/           per-milestone specs, written before code
├── app/                 GyroPad Android app (Phase 0) — scaffolded at M1
└── firmware/            ESP32 firmware (Phase 1+)
```

## Status log

- **2026-11-07** — Project created. Research completed and sourced (competitors, open-source vetting, feasibility, economics). Eight decisions recorded. Full documentation set written file-by-file. Next: M1 spec, then the app.
- **2026-11-07** — Agent persona defined ([PERSONA.md](PERSONA.md), [ADR-009](docs/DECISIONS.md)): staff-engineer craft standard + mandated internet-research protocol. Documentation set now 11 files.

## License

Proprietary — all rights reserved. Per-component licensing is decided before any public release ([ADR-007](docs/DECISIONS.md)).

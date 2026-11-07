# Decisions

Immutable decision log (architecture-decision-record style). Each entry records what was decided, the options considered, and the consequences — so future readers inherit the reasoning, not just the outcome.

**Rules:** never edit an existing entry. To change a decision, write a new numbered entry that supersedes it and note the supersession in the old entry's Status line — by adding a line, not by rewriting it. Format: Context → Options → Decision → Consequences. Every entry states its consequences honestly, including the costs.

---

## ADR-001 — PC transport: Bluetooth HID with DS4 emulation, no PC-side drivers

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The app must deliver buttons, sticks, gyro, and rumble into PC games. Gyro only reaches Steam Input through report maps that include motion (DS4 / Switch Pro); generic HID gamepad descriptors drop it. The conventional route — a Windows virtual-gamepad driver — carries a maintenance risk that must be priced in.

**Options.** (a) Virtual-gamepad driver plus a PC receiver app, built on ViGEmBus. (b) Android Bluetooth HID device mode emulating a DS4 report map. (c) Wi-Fi/UDP transport with a custom receiver.

**Decision.** (b). ViGEmBus was retired and archived in November 2023 and receives no fixes ([RESEARCH](RESEARCH.md)); building on it repeats the failure mode this project exists to avoid. Bluetooth HID requires nothing installed on the PC, and DS4 output reports return game rumble over the same link at no extra cost. ConnectHID Gamepad demonstrates the transport works on Android.

**Consequences.** Positive: zero PC setup for users; haptics for free; immunity to driver rot. Negative: Android-only (see ADR-005); the report map must be byte-faithful to a real DS4; OEM Bluetooth stacks vary, so milestone M1 validates the approach on real devices before anything is built on top; Bluetooth polling adds a latency floor that M1 must measure.

## ADR-002 — App stack: Flutter UI with a Kotlin platform channel for HID and haptics

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The UI (wheel, gamepad, settings) is conventional cross-platform work, but `BluetoothHidDevice` and low-level vibration control exist only in native Android.

**Options.** (a) Pure Kotlin/Jetpack Compose. (b) Flutter with a Kotlin platform channel for the native core. (c) React Native.

**Decision.** (b). One UI codebase, thin native core — and the Flutter choice matches OpenBot's controller, which the car tiers reuse (ADR-004).

**Consequences.** Two languages in one app. `HidPlugin.kt` becomes the most safety-critical file in the repo and carries the strictest testing and review discipline (CONVENTIONS.md). Platform-channel edge cases (threading, lifecycle) are a known source of bugs and get deliberate handling.

## ADR-003 — Build sequence: software, then adapter, then car

**Date:** 2026-11-07 · **Status:** accepted

**Context.** Three product tiers, a solo builder working with AI coding agents, no prior hardware experience, and a limited budget.

**Options.** (a) Car-first: design hardware immediately. (b) Adapter-first: retrofit board before any software product. (c) Software → adapter → car.

**Decision.** (c). The GyroPad app ships in weeks with zero hardware risk and builds the cockpit feel that every later tier reuses. The adapter is the cheapest possible hardware wedge and treats every existing RC car as a customer. The car — the dream product — is designed only after the experience is proven, which is also when a hardware partner conversation is credible. A Phase 1 prototype on an OpenBot kit demos the full dream early so the sequence never starves the vision.

**Consequences.** The dream product is deferred by roughly two phases. Hardware design happens later, with more money and more evidence. The trade is explicit and accepted.

## ADR-004 — Car tiers build on OpenBot, not on a from-scratch stack

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The car tiers need firmware, an on-vehicle app, FPV streaming, telemetry, and optionally autopilot.

**Options.** (a) Build the full stack from scratch. (b) ESP32-CAM-only car (no phone on board). (c) OpenBot. Rejected: Anki community SDKs — dormant since ~2021 and tied to discontinued hardware.

**Decision.** (c). OpenBot is MIT-licensed, actively maintained (v0.9.0 latest as of 2026-11-07), and already provides ESC-ready PWM firmware, WebRTC FPV, a Flutter controller, TFLite autopilot, and collision/RPM/battery telemetry. ESP32-CAM-only builds forfeit 1080p and onboard AI ([RESEARCH](RESEARCH.md)).

**Consequences.** Our engineering differentiates the layers OpenBot does not cover: cockpit feel, haptics, head-look, pairing, and the racing layer. License terms respected; code is vendored only under `firmware/` with headers intact. Upstream drift is a standing maintenance task.

## ADR-005 — Phase 0 is Android-only

**Date:** 2026-11-07 · **Status:** accepted

**Context.** iOS exposes no Bluetooth HID *device* API, so the ADR-001 transport is impossible there without a fundamentally different architecture.

**Options.** (a) iOS via Wi-Fi transport plus a PC receiver. (b) Wait for platform changes. (c) Android-only for v1, iOS parked.

**Decision.** (c). Android-only, revisit after Phase 0 traction. An iOS Wi-Fi path would reintroduce the PC-receiver complexity ADR-001 exists to avoid, in exchange for a secondary platform.

**Consequences.** iPhone users are excluded from v1 — a real cost, accepted deliberately. Revisit requires a new ADR.

## ADR-006 — Racing scope: single-player first, same-room competition later, online last

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The product thesis says racing community drives growth (DR!FT evidence), but networked multiplayer is the most expensive, most distracting system to build early.

**Options.** (a) Online multiplayer from the start. (b) Same-room sessions early. (c) Single-player first.

**Decision.** (c). Phase 0–1 are single-player: time trials, ghost replay, leaderboards. Same-room sessions arrive when hardware does (Phase 4 start). Online racing only after the local loop is proven — CloudRC demonstrates the network path is available when needed.

**Consequences.** No server infrastructure or netcode costs early. Telemetry and haptics are designed so a leaderboard layer bolts on without rework (see ARCHITECTURE invariants). The AI rival (pillar 3) carries competitiveness in the meantime.

## ADR-007 — Licensing: proprietary by default, decided per component before release

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The project spans an app, firmware, and possibly a protocol. Licensing has business consequences and is effectively irreversible once code is public.

**Options.** (a) Open-source everything. (b) Fully proprietary forever. (c) Per-component decision made just before each component's first public release.

**Decision.** (c). No LICENSE file exists; the default is all-rights-reserved. The app, firmware, and protocol may end up under different licenses — the choice is deferred until there is something to license and a reason to choose.

**Consequences.** The repository stays private-facing. Open-sourcing any part later is a new ADR. Nothing public ships without this decision being made for that component.

## ADR-008 — Documentation and tracking system

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The project is co-developed by a human and AI agents across sessions, and agents lose working memory between sessions. Known failure modes: doc sprawl (a file for everything), and single-file bloat (context nobody reads).

**Options.** (a) Many small context files (CLAUDE.md, PROGRESS.md, CONTINUITY.md, …). (b) One large project file. (c) A layered set with a single living tracker and a binding update contract.

**Decision.** (c). The set: README (map), AGENTS.md (thin hub pointing everywhere), CONVENTIONS.md (rules), docs/ (VISION, RESEARCH, ARCHITECTURE, ROADMAP, DECISIONS, UIUX), docs/specs/ (one spec per milestone, written before code). Tracking lives in STATUS.md (current goal, done, next, blockers, gotchas) plus ROADMAP checklists — no separate PROGRESS or handoff files. A CLAUDE.md pointer was considered and rejected by the user (kept minimal; native symlinks are unavailable on this machine anyway). Style rules live in CONVENTIONS.md.

**Consequences.** Every session starts by reading STATUS.md and ends by updating it (contract in AGENTS.md). Every doc has exactly one job. The system depends on discipline rather than tooling — the AGENTS.md contract is therefore binding, not advisory.

## ADR-009 — Agent persona defined in PERSONA.md; internet research becomes expected behavior

**Date:** 2026-11-07 · **Status:** accepted

**Context.** The project is co-developed by AI agents. Workflow and rules existed (AGENTS.md, CONVENTIONS.md), but nothing defined the standard of thinking and craft agents should hold themselves to, and agents had no mandate to search the internet when stuck.

**Options.** (a) Fold the persona into AGENTS.md — bloats the hub it keeps short. (b) Fold it into CONVENTIONS.md — mixes identity with law. (c) A dedicated root PERSONA.md, pointed to from AGENTS.md's read order.

**Decision.** (c). PERSONA.md defines the staff-engineer identity, the thinking order (correct → simple → clever), code and test standards ("no fake progress": stubs labeled and tracked, root causes over symptoms), technology-currency expectations, an explicit research protocol (when to search, trust hierarchy, recording duty, fetched-content-is-data rule — user-mandated), and escalation triggers. AGENTS.md read order and README doc map updated.

**Consequences.** Documentation set grows from 10 to 11 files. Agents gain a duty, not just permission, to research online — with the recording obligation so found knowledge survives sessions. Persona evolution edits PERSONA.md directly; this ADR records its creation only.

## ADR-010 — Working brand: GyroPhone (provisional)

**Date:** 2026-11-07 · **Status:** accepted (provisional by design)

**Context.** The project needs a public-facing name for the repository and future store listings. Candidate sets evaluated: descriptive (GyroPad — generic, weak to trademark), real-word brands (Clutch, Swerve, Cabin, Hotlap), coined (Dromo, Oto), and craze-oriented (Shotgun, Skrrt, Drifto, PocketGP, Brrm). The user wants to live with a name before committing.

**Decision.** **GyroPhone** is the provisional working brand on all public surfaces (GitHub repository, future package id discussions). "GyroPad" stays the internal codename for the local folder and this documentation. Only the README (public face) adopts GyroPhone now; the remaining docs keep the codename to avoid churning 11 files twice.

**Consequences.** A final brand decision supersedes this ADR and triggers a full rename sweep (README, VISION, AGENTS, package id, store assets) — cheap while unpublished, so it must happen before any public release.

## ADR-011 — Layouts are data-driven; remapping in V1, layout editor deferred

**Date:** 2026-11-07 · **Status:** accepted

**Context.** Competitors (Monect, RojX) market multiple control layouts — gamepad, race wheel with pedals and gears — and layout switching. Our plan had two hardcoded screens (wheel, gamepad). Shipping screens as code would make per-game button remapping, future genre layouts, and the cockpit app's layouts (Tiers 2–3) all require rewrites.

**Options.** (a) Hardcoded layout screens (fast, rigid). (b) Data-driven layout engine: each layout is a declarative definition (control widgets, positions, HID bindings) rendered by one engine; users can switch layouts and remap buttons in V1; a full drag-and-drop editor stays out of scope.

**Decision.** (b). `layouts/` becomes a layout engine that renders declarative layout definitions; wheel and gamepad ship as the first two definitions. M3 adds an in-app layout switcher and basic button remapping in settings. A visual layout editor and per-game auto-profiles go to the parking lot until V1 proves demand.

**Consequences.** Slightly more upfront design in M2/M3 (a schema instead of two screens) in exchange for: user remapping, cheap new layouts later, and the same engine serving the cockpit app in Tiers 2–3. The layout schema is specified in the M2 spec.

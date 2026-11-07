# Roadmap

The build order, the milestones, and what "done" means for each. One job: sequence the work so the riskiest unknowns are resolved first and every phase ships something real.

Current position lives in [STATUS.md](../STATUS.md) (working narrative) and in the checkboxes below (durable progress). Success criteria and the product vision live in [docs/VISION.md](VISION.md); this file holds the plan, not the pitch.

## How milestones work

- **Spec first.** Every milestone begins by writing its spec in `docs/specs/` — goal, requirements, acceptance criteria, task list — approved by the user before any code. Specs are the source of truth; code implements specs.
- **Acceptance criteria are the definition of done.** A checkbox is ticked only after the criterion passes. Nothing is "done" on intent.
- **Each milestone has an explicit out-of-scope list.** If work is not in scope, it waits — even if it is tempting, even if it is easy (see the never-do list in [CONVENTIONS.md](../CONVENTIONS.md)).
- Estimates are **targets, not promises**, paced for one human plus AI agents.

## Sequencing logic

M1 before everything because the Bluetooth HID transport is the one unknown that can invalidate the product — if it fails, the plan changes, so it is tested on real devices before anything is built on top. M2 before M3 because gyro steering is the product's identity; M3 ships because shipping teaches. Phase 1 (prototype car) precedes Phase 2 (retrofit board) because the cockpit software must exist before we can sell a board that runs it. Phase 3 (our car) comes only after the experience is proven on the adapter. Phase 4 (racing) comes last because community needs players first.

Dependency chain: **M1 → M2 → M3 → Phase 1 → Phase 2 → Phase 3 → Phase 4.**

## Phase 0 — GyroPad MVP (Android) — current

Target: a stranger installs nothing on their PC, pairs their phone, and drives a Steam racing game with gyro and rumble inside five minutes.

### M1 — "Hello, gamepad": phone pairs as a DS4 — in progress (transport proven)

**Goal.** Prove the transport on real devices. This is the spike that decides whether the plan holds.

**Spec:** `docs/specs/M1-pair-as-ds4.md`.

**In scope:** Kotlin `BluetoothHidDevice` plugin (SDP app record, DS4 report descriptor, register/connect flow); input-report packing for buttons and sticks; minimal temporary status screen (per [UIUX.md](UIUX.md) interim rule); connection state machine with disconnect/reconnect handling; input-path latency measurement.

**Out of scope:** gyro and sensor fusion, wheel layout, haptics, settings, anything about cars.

**Acceptance criteria:**
- [x] M1 spec written and approved
- [x] Phone registers as a DualShock 4; PC pairs from Bluetooth settings (2026-11-08, Nord 5; DS4 SDP identity + small-report descriptor — see the spec's R4/Pitfalls for the documented deviation)
- [x] Buttons and sticks visible and responsive in a Windows gamepad tester (2026-11-08, joy.cpl, user-confirmed)
- [ ] Works on the user's device and at least one other (Nord 5 ✓; Nothing Phone 1 pending)
- [x] State machine survives disconnect/reconnect without app restart (demonstrated live: BT toggles, app restarts, re-pair cycles — auto re-register + device-initiated reconnect)
- [ ] Input-path latency measured and recorded against the budget in [ARCHITECTURE.md](ARCHITECTURE.md) (instrumented; readout pending)

**Exit:** a working pairing demo on the user's PC; measurements logged.

### M2 — "The wheel": gyro into Steam — not started

**Goal.** Real gyro steering, the product's identity, working in a real game.

**Spec:** `docs/specs/M2-wheel.md` (written after M1 passes).

**In scope:** sensor fusion service (rotation vector + gyro); `WheelModel` (steering-axis choice, configurable rotation range up to 900°, deadzone, sensitivity, response curve, re-zero control); motion block population in the input report; racing-wheel layout v1; Steam Input template config and a short setup guide.

**Out of scope:** gamepad layout, haptics, settings screen, car anything.

**Acceptance criteria:**
- [ ] M2 spec written and approved
- [ ] Steam Input receives gyro; the template config steers a racing game (BeamNG or Assetto Corsa)
- [ ] Rotation range, deadzone, and sensitivity are configurable and take effect live
- [ ] Re-zero works and is reachable during play
- [ ] No manual re-zero needed during a 10-minute session (drift check)
- [ ] Device test passes per the byte-faithfulness rule ([ARCHITECTURE.md](ARCHITECTURE.md))

**Exit:** the user drives a Steam racing game with the phone as the wheel.

### M3 — "The feel": haptics, gamepad, ship — not started

**Goal.** The full Phase 0 product: both layouts, real haptics, shippable.

**Spec:** `docs/specs/M3-feel.md`.

**In scope:** gamepad layout; **layout switcher + basic button remapping** (the layout engine renders declarative definitions — [ADR-011](DECISIONS.md)); settings screen (rotation range, sensitivity, deadzones, haptics on/off/intensity, steering-axis choice); `HapticEngine` with rumble replay from output reports; onboarding polish; APK build; the Steam setup guide shipped with it.

**Out of scope:** anything car-related, iOS, theming, store release process (parking lot).

**Acceptance criteria:**
- [ ] M3 spec written and approved
- [ ] Game rumble reaches the phone as vibration; intensity levels are distinguishable
- [ ] Gamepad layout complete and usable
- [ ] Layouts switchable in-app; buttons remappable in settings ([ADR-011](DECISIONS.md))
- [ ] `flutter analyze` and `flutter test` green
- [ ] A person who has never seen the app completes pairing → driving in five minutes, with no help
- [ ] APK + setup guide produced

**Exit:** demo video of the full experience; Phase 0 closes.

## Phase 1 — prototype cockpit car (plan level; detailed when reached)

**Goal.** Prove the cockpit experience on real hardware and make the video that explains the product.

- Acquire an OpenBot RTR kit (~$50–60) and dedicate a spare Android phone
- Run upstream OpenBot as-is; verify FPV latency against the [ARCHITECTURE.md](ARCHITECTURE.md) budget
- Fork the Flutter controller into the cockpit app; complete the UI/UX design pass first ([UIUX.md](UIUX.md))
- Haptic mapping: collision and RPM telemetry → vibration patterns
- Head-look: cockpit phone gyro pans the FPV view
- AI rival: OpenBot autopilot as the opponent
- **Exit:** one video showing haptic cockpit, head-look, and AI rival; latency measurements recorded

## Phase 2 — retrofit-any-car board (plan level)

**Goal.** The ecosystem wedge: turn existing RC cars into cockpit cars.

- Board spec: ESP32-S3 + camera; control-link choice decided here (the [ARCHITECTURE.md](ARCHITECTURE.md) deferred list)
- Pairing-code provisioning; wiring guide for common car types (toy PWM, hobby ESC)
- BOM target $6–12; hand-assembled beta batch
- Community beta through RC channels
- **Exit:** ten external users retrofit their own cars without hands-on help

## Phase 3 — our designed car (plan level)

**Goal.** The dream product, designed once the experience is proven.

- Industrial design; BOM target $25–35
- Certification path: FCC/CE and toy safety; freedom-to-operate review before launch ([RESEARCH.md](RESEARCH.md))
- Manufacturing partner (Shantou/Shenzhen); pilot batch
- **Exit:** sellable product page and first production batch

## Phase 4 — racing ecosystem (plan level)

**Goal.** The layer that turns toys into a hobby.

- Same-room sessions; leaderboards; ghost replay
- Leagues and events (the DR!FT model, with eyes)
- Online racing over WebRTC/4G once local play is solid
- **Exit:** the first community league event

## Parking lot

Not scheduled, decided later — each enters scope only through a user decision (and an ADR if architectural):

- iOS support (blocked by platform; see [ADR-005](DECISIONS.md))
- PC receiver companion for non-Steam use cases
- Full drag-and-drop layout editor + per-game auto-profiles ([ADR-011](DECISIONS.md) — revisit when V1 users ask)
- More genre layouts (touchpad, FPS preset) — data-driven engine makes these cheap, demand decides
- Localization; CI/CD when the repo is hosted; app-store release process
- License choices per component ([ADR-007](DECISIONS.md))

## When plans change

Re-scoping is the user's call. Architectural consequences go to a new ADR first; then this document and [STATUS.md](STATUS.md) update in the same change. Milestone numbers are never reused — a re-scoped M2 becomes M2.1.

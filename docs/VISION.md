# Vision

GyroPad turns the phone a person already owns into a cockpit controller. It starts as a controller for PC games and grows into a controller for real cars. Same app, same controls, one product line built in three steps.

This document explains what we are building, why it exists, and what we refuse to do. Evidence and sources live in [RESEARCH.md](RESEARCH.md); decisions live in [DECISIONS.md](DECISIONS.md).

## The product

| Step | Product | What it is |
|------|---------|------------|
| 1 | GyroPad app | An Android app: 900° gyro steering wheel, full gamepad, and haptic feedback for PC games, connected over Bluetooth HID. Nothing gets installed on the PC. |
| 2 | Retrofit board | A small ESP32 board with a camera that wires into an RC car's servo and ESC leads. The phone replaces the car's stock controller. |
| 3 | FPV car | Our own car, designed around the cockpit experience: camera at the driver's position, control unit paired to the app with a code. |

The order is deliberate. Software ships first with no hardware risk and reaches users in weeks. The adapter is cheap hardware that treats every existing RC car as a potential customer. The car gets designed only after the cockpit experience is proven on real hardware.

## Why it exists

Three observations, each sourced in [RESEARCH.md](RESEARCH.md).

The expensive part of this product category is already in people's pockets. A mid-range phone carries a gyroscope, a haptic motor, a 1080p camera, and more compute than any toy in this market. Dedicated products re-sell those same components at a markup and lock them behind closed apps that outlive their companies badly.

The category keeps dying while demand does not. Anki Overdrive shut down in 2019, and its revival keeps the hardware discontinued. DJI's RoboMaster S1 sold at $500, is discontinued, and users report its app already fails to open. VR Real Feel Racing shipped an app that broke on the stores. Each collapse leaves a community with working hardware and no software future.

Racing is what turns a toy into a hobby, and no camera product has it. Sturmkind's DR!FT, which has no camera at all, sustains league finals, seasonal events, and a club app across 2024 and 2025. The products that do carry cameras, like Real Racer and CloudRC, have no racing layer and no community tooling. Nobody has combined the phone cockpit, camera cars, and a racing community in one system. That combination is the business.

## Who it is for

**PC gamers who want a wheel but not the hardware bill.** Real wheels cost $150 to $500 for something most people use occasionally. This crowd accepts software answers; the existing ones have weak gyro handling and no haptics worth the name.

**The existing RC installed base.** Owners of $20 to $100 cars who already know the fun and want more from hardware in a drawer. The retrofit board sells to them without asking them to buy a new car.

**Anyone who wants to be the driver, not the operator.** Kids, teens, and gadget buyers. Holding a screen that shows the driver's seat, with the car answering your hands, is the product. Everything else exists to deliver that moment.

## Why this can win

The claim rests on structure, not enthusiasm.

The incumbents are positioned where copying us is expensive for them. Hardware companies such as Kobotix, Sturmkind, and CloudRC ship closed apps and sell fixed-function toys; an open controller that also runs on PC games and on other brands of cars contradicts their model. Software incumbents such as Monect and RojX have no hardware path, and neither treats haptics as a product. The one-app-spans-both position is available, and we are taking it.

The build also avoids the usual death spiral of hardware startups. The car stack stands on OpenBot, an actively maintained MIT-licensed project that already provides the firmware, FPV streaming, autopilot models, and telemetry we need. Our engineering goes into the layers that differentiate: the cockpit feel, the haptics, the pairing, the racing layer.

## The four pillars

Four feature bets define the product. Nothing else enters scope until these exist.

1. **A true-haptic cockpit.** Vibration that carries information: engine speed, impacts, drift, terrain. Current products treat rumble as a decoration or omit it entirely. We treat it as a channel.
2. **Driver-seat camera with head-look.** The camera sits where the driver would, and tilting the phone looks around corners. This is the sensation of sitting inside the car, and a phone gyroscope makes it nearly free to build.
3. **An AI rival.** OpenBot's autopilot models let a car race the player without a second human in the room. Single-player stays competitive, which matters because multiplayer is a later phase.
4. **The retrofit-any-car board.** The entry SKU that recruits the existing RC fleet into the ecosystem. Closed competitors cannot sell it without opening their platforms, which is exactly why we can.

## Non-goals

These are binding on everyone who works in this repo, including agents. Non-goals exist because scope creep is the default failure mode of this kind of project.

- **No iOS support in Phase 0.** iOS exposes no Bluetooth HID device API. Revisit only after Android traction.
- **No online multiplayer in early phases.** Same-room play with leaderboards comes first; networked racing is Phase 4.
- **No analog 5.8 GHz FPV links.** Local digital Wi-Fi sits in the proven 40–100 ms range, which cars do not need to beat. Analog adds cost and radio complexity for no product gain at our speeds.
- **No universal-remote features.** Mouse, keyboard, and media control are Monect's business. We do one thing deeply.
- **No custom ML research.** The autopilot uses OpenBot's existing policy models. We tune them for racing; we do not train our own in early phases.
- **No theming, skins, or portrait UI.** It is a cockpit app: landscape, dark, one visual language, defined in [UIUX.md](UIUX.md).

## What success looks like

Phase 0: a stranger installs nothing on their PC, pairs their phone, and is driving a Steam racing game with gyro steering and rumble inside five minutes.

Phase 1: one demonstration video, showing the haptic cockpit, the head-look camera, and an AI rival, makes the category legible to people who have never heard of it.

Long term: a racing community on top of the hardware line. Leaderboards first, same-room leagues next, online racing when the local loop is proven. DR!FT demonstrated that the community forms when racing exists; no camera product has ever given that community eyes.

## What could kill this

- Phone-to-PC gyro fails on common Bluetooth stacks. This is why milestone M1 is the first thing we build, on real devices, before anything else.
- Digital FPV latency does not feel good enough to drive by. The architecture is LAN-first and existing products ship at this range, but we verify the feel with a prototype before any hardware investment.
- Monect ships serious haptics and a hardware line. Unlikely, but its free gamepad layout competes with ours head-on; depth of cockpit feel and the racing layer are our answer.

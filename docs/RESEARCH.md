# Research

Reference document: market facts, competitor status, open-source evaluation, and technical feasibility findings behind the decisions in [DECISIONS.md](DECISIONS.md).

Research completed **2026-11-07** using public web sources, GitHub repositories, and app-store listings. Every factual claim links to its source. Maintenance rules are at the end of this file.

## How to read this document

Each material claim carries one of three confidence labels:

- **Verified** — a primary source was read directly (repository, release page, vendor support page, store listing, pricing page).
- **Reported** — a secondary source (review, news post, community thread); treated as accurate but not re-checked against the vendor.
- **Assessed** — our analysis or estimate; the reasoning is stated alongside.

## Market

| Segment | Figure | Source | Confidence |
|---------|--------|--------|------------|
| RC toys | $7.6B (2025) → $13.8B (2034), CAGR ≈ 6.8% | Market Research Future | Reported |
| RC toys (alternate estimate) | $7.97B (2025) | secondary analyst | Reported |
| Connected toys | $10.19B (2025) → $47.03B (2035) | Market Research Future | Reported |
| Smart toys | $14.4B–$22.4B (2025), 12–16% CAGR | range across analysts | Reported |

Reading (Assessed): absolute sizes differ by analyst and by definition, but the direction is consistent — a ~$8B hardware base with the app-connected slice growing fastest. That slice is what this project sells into.

## Competitors — phone as controller for PC games (Tier 1)

| Product | Model | Price | Gyro quality | Haptics | Hardware bridge |
|---------|-------|-------|--------------|---------|-----------------|
| [Monect PC Remote](https://www.monect.com) | free app + PC receiver | free | weak (community-reported) | none | none |
| [RojX](https://rojx.io/pricing) | subscription | $1.99/mo, $11.99/yr, 7-day trial | strong claims (900° wheel, ~3 ms) | none | none |
| [ConnectHID Gamepad](https://play.google.com/store/apps/details?id=com.connecthid.gamepad) | free app | free | basic | none | n/a (is the bridge) |
| Touch Racer, DroidWheel | PC utilities | free–cheap | basic | none | none |

**Monect PC Remote.** The free incumbent: phone as gamepad, touchpad, keyboard, and motion device over Wi-Fi or USB, with G-sensor steering and gyro-aim modes. Community feedback on gyro precision is negative where it is discussed — r/GyroGaming users describe it as "not great" and share manual layout workarounds (Reported). Its positioning is universal-device-remote, which spreads it thin (Assessed).

**RojX.** The paid newcomer: smartphone as low-latency PC controller and virtual steering wheel over Wi-Fi or USB, aimed at sim racing (BeamNG, Assetto Corsa). Advertises up to 900° wheel rotation and ~3 ms latency; subscription pricing verified on [their pricing page](https://rojx.io/pricing) (Verified for pricing; latency claim is vendor marketing, untested by us). No haptics, no hardware path (Reported).

**ConnectHID Gamepad.** Small Android app that pairs the phone as a Bluetooth HID gamepad to PCs and Android TVs. Existence is the important part: it demonstrates the exact transport GyroPad depends on (ADR-001). Limited polish; no motion focus (Reported).

**Touch Racer / DroidWheel.** PC-side utilities that read a phone as a tilt steering wheel for sim games; niche tools, no ecosystem (Reported).

Gap (Assessed): no product combines fused-sensor gyro precision, event-driven haptics, and a bridge to real hardware. Haptics is the most neglected dimension — none of the four treat vibration as more than an afterthought.

## Competitors — camera toy cars (Tiers 2–3)

| Product | Price | Camera/FPV | Racing layer | Status (as of 2026-11) |
|---------|-------|------------|--------------|------------------------|
| [KOBOTIX Real Racer](https://pocketables.com/2022/11/kobotix-real-racer-real-fun.html) | $129 launch, ~$149 on Amazon | 720p Wi-Fi FPV | none | active |
| [DR!FT (Sturmkind)](https://sturmkind.com/en) | €129.90–€199.90 | none | leagues, events, club app | active |
| [CloudRC](https://store.cloudrc.com/products/cloudrc-unlimited-range-fpv-rc-car-ready-to-run-4g-5g-real-time-video-voice-streaming-customized-products) | RTR packages | 4G/5G FPV + two-way voice | none | active |
| Turbo Racing C73/C74, SNT/Diatone Q25 | micro-car pricing | phone/goggle FPV | none | active, viral |
| Anki Overdrive | — | none | was the category's community flagship | dead |
| [DJI RoboMaster S1](https://www.dji.com/support/product/robomaster-s1) | $499 at launch | FPV camera | app battles/races | discontinued |
| [Sphero RVR+](https://help.sphero.com/sphero-support/discontinued-sphero-products) | education pricing | none | education program | active, education pivot |

**KOBOTIX Real Racer.** The closest analog to our Tier 3: FPV RC car, phone in a wheel cradle, tilt steering, 720p low-latency video, ~25 km/h. Reviews from 2022–2024 praise the immersion and note imprecise handling ("fairly clumsy" per [Gadgetoid](https://gadgetoid.com/2022/11/25/kobotix-real-racer-fpv-rc-car-review)). Company shows no shutdown signals: brand refresh November 2023, Quest XR app July 2024, Android app updated August 2024 (Reported). No haptics, no multiplayer, no community tooling found in any review or listing (Assessed from absence).

**DR!FT (Sturmkind).** The community proof: 1:43-scale cars with simulated driving physics, no camera, controlled by phone. Sustained organized competition — Online Games finale March 1–2, 2025 (Speyer), "Twin Battle" mode announced April 2025, Speed Arena track sold out its first batches, DR!FTCLUB app with trophies and rally events (Reported, official channels). Demonstrates that phone-controlled toy cars support a durable racing scene.

**CloudRC.** 4G/5G teleoperation of RC cars with live video and two-way voice; "unlimited range" within cellular coverage. Community feedback confirms it works on 4G; touch-screen control is regarded as inferior to a wheel-and-pedal setup (Reported). Relevant to Phase 4 as evidence that networked racing is technically viable today.

**Turbo Racing C73/C74 and SNT/Diatone Q25.** Viral micro FPV cars (1:76 scale) driven through phone or bundled goggles. Reviewers praise scale realism and criticize toy-grade dynamics — "jerky throttle," per [Walmart](https://www.walmart.com/reviews/product/18633912234) and [Oscar Liang](https://oscarliang.com/turbo-racing-mini-rc-car) (Reported). No software ecosystem beyond the stock app.

**Anki Overdrive.** Anki shut down in 2019; Digital Dream Labs acquired the assets and rebranded back to Anki. Hardware is discontinued as a retail product; only app version 2.6 receives support; no new development ([Wikipedia](https://en.wikipedia.org/wiki/Anki_(company)), [vendor FAQ](https://support.anki.bot/article/329-overdrive-2-6-frequently-asked-questions)) (Verified). Community reverse-engineering SDKs have been dormant since ~2021 — which is why they are rejected as a base.

**DJI RoboMaster S1.** $499 robot car with FPV and app-based battles, launched 2019, never refreshed, no longer sold by DJI. Users reported the app refusing to open after updates (2024 threads); DJI ended support for other older products the same period (Reported). Confirms the affordable-FPV gap is real and unowned.

**Sphero RVR+.** In production with an open public SDK, but positioned for education; not a consumer racing product (Verified against vendor pages). Useful only as evidence that "vehicle + open SDK" survives in the education niche.

**VR Real Feel Racing.** Included as the cautionary tale: store reviews report the app crashing on connection to the bundled wheel, effectively killing the product ([App Store reviews](https://apps.apple.com/gb/app/1152843339?see-all=reviews&platform=iphone)) (Reported). Closed software with no maintenance path is how this category's products die.

## Open-source foundations

| Project | License | Activity at research date | Verdict for us |
|---------|---------|---------------------------|----------------|
| [OpenBot](https://github.com/ob-f/OpenBot) | MIT | 3.6k stars, 1,227 commits, v0.9.0 latest | **base for Tiers 2–3** |
| [ViGEmBus](https://docs.nefarius.at/projects/ViGEm/End-of-Life) | — | retired and archived Nov 2023 | **must not depend on** |
| [DSU/cemuhook protocol](https://github.com/vcen-cemuhook-protocol/cemuhook-protocol) | open | supported by Dolphin, Cemu, Yuzu | optional motion path |
| [hx-esp32-cam-fpv](https://github.com/RomanLut/hx-esp32-cam-fpv) | open | maintained | adapter camera option |
| [ESP32_WebSocket_Car](https://github.com/Hiroshimeow/ESP32_WebSocket_Car) | open | maintained | streaming option |
| [ESPNowCam](https://github.com/topics/esp32cam) | open | active | routerless link option |
| [VirtualGamePad](https://github.com/kitswas/VirtualGamePad) | open | actively maintained | app-pattern reference |
| [Donkey Car](https://github.com/autorope/donkeycar) | MIT | v5 in testing | reference only (Pi, self-driving niche) |
| Anki community SDKs ([1](https://github.com/psteinroe/anki-overdrive-sdk), [2](https://github.com/jacopotagliabue/anki-drive-python-sdk)) | open | dormant since ~2021 | rejected (dead hardware) |

**OpenBot** (Verified): Android app runs on a phone mounted to the vehicle — camera, TFLite autopilot policies, sensor logging — and talks to ESP32/Arduino firmware that drives motors with ESC-ready PWM and returns telemetry (wheel RPM, battery, collision detection). The Flutter controller app (v0.8+) adds a second-phone control path with WebRTC video, tilt steering, and gamepad support over BLE or Wi-Fi. Release dating note: the releases page lists v0.9.0 (October 7) as latest at retrieval; the page does not display the year, so activity is stated as "as of research date" rather than a year.

**ViGEmBus** (Verified): Windows kernel driver for virtual Xbox/DS4 gamepads, retired and archived November 2023 over a trademark conflict. Final versions still function but receive no fixes, and no successor driver has broad adoption. Consequence: GyroPad's PC path must not require it — hence ADR-001 (phone emulates a DS4 over Bluetooth HID; motion rides in the DS4 report map; Steam Input maps gyro to wheel axes; precedent: ConnectHID).

Conclusion (Assessed): no better base than OpenBot exists for the car tiers given our constraints (maintained, permissive license, phone-as-brain + FPV + autopilot included). No better transport than Bluetooth HID exists for Tier 1 given the driver-rot risk demonstrated by ViGEmBus.

## Feasibility findings

### Retrofit (Tier 2)

An RC receiver is a pulse generator: 1000–2000 µs pulses at ~50 Hz on servo and ESC signal leads. An ESP32 reproduces this directly, and the pattern is documented repeatedly — [Instructables full rebuild](https://www.instructables.com/Rebuild-an-RC-Car-With-ESP32-Arduino-Code), [Hackster ESP32-CAM replacing a toy's receiver](https://www.hackster.io), DIY ESP32+ESP-NOW transmitter/receiver pairs (Verified). OpenBot firmware already converts control commands to ESC-ready PWM. The retrofit board is therefore wiring plus provisioning, not invention.

### Gyro into PC games (Tier 1)

Standard HID gamepad descriptors do not carry motion data. Emulating a DualShock 4 (or Switch Pro) report map includes motion in the input report, and Steam Input maps that gyro to arbitrary axes including steering. ConnectHID demonstrates the Android side. Constraint: the emulated report map must match a real DS4 byte-for-byte or Steam and games will misread it (Verified mechanism; Assessed risk).

### Haptics

DualShock 4 output reports carry the rumble intensity a game sets. Our app receives them over the same HID link and replays them through the phone's Vibrator API — game-driven haptics with no PC-side plumbing. In car tiers, OpenBot telemetry (collision, wheel RPM, battery) enriches the same engine with physical events (Verified mechanism; Assessed product value).

### Latency budget (video)

| Link | Glass-to-glass | Source | Confidence |
|------|----------------|--------|------------|
| Analog 5.8 GHz FPV | ~5–25 ms (30–50 ms incl. sensor in some rigs) | [fpvbuilder.io](https://fpvbuilder.io/en/compare/analog-vs-digital-fpv), [UAVModel](https://blog.uavmodel.com/fpv-goggles-guide-analog-vs-digital-systems-compared) | Reported |
| Digital HD systems | HDZero ~14 ms, Walksnail ~22 ms | same | Reported |
| Tuned LAN MJPEG/H.264 | ~36–40 ms pipeline | [Raspberry Pi forums](https://forums.raspberrypi.com/viewtopic.php?t=186928) | Reported |
| WebRTC over internet | ~50–150 ms (transport itself ~10 ms) | [Transitive Robotics](https://transitiverobotics.com/blog/webrtc-latency-breakdown) | Reported |

Reading (Assessed): drone FPV pilots want 20–30 ms, and 200 ms-class streams are unusable for manual flight. Cars are slower than drones, and Real Racer ships digital Wi-Fi at this class with reviews calling the experience fun. Our LAN-first target of 40–100 ms sits inside the demonstrated-fun zone; internet play is a later, separate path.

### Economics

| Item | Figure | Source | Confidence |
|------|--------|--------|------------|
| Wi-Fi FPV toy cars, wholesale (China) | $7.80–$13 entry, $17–26 mid, $48–70 hobby | Alibaba/Made-in-China listings at research date | Reported |
| Materials share of product cost | 40–60% | BOM analyses (AGS Devices et al.) | Reported |
| Real Racer retail | $129 launch, ~$149 on Amazon | listings, reviews | Verified |
| Subscription benchmark | RojX $11.99/yr | [rojx.io/pricing](https://rojx.io/pricing) | Verified |

Implication (Assessed): a camera car at $25–35 COGS supports $99–149 retail; the retrofit board at $6–12 BOM supports ~$49; a $12–15/yr subscription is within the proven willingness to pay.

### Intellectual property

Public searches surfaced no Kobotix patent filings and no litigation concerning phone-as-steering-wheel FPV control. The interaction pattern is widely published across Monect, RojX, and hobby builds dating back to at least 2016. This is not legal clearance: a formal freedom-to-operate review is required before hardware launch (Assessed).

### Platform constraints

- **iOS** exposes no Bluetooth HID *device* API, so Tier 1 is Android-only in v1 (ADR-005).
- **Windows** requires no drivers on the Bluetooth-HID path — that is the point of ADR-001.

## Keeping this current

- Every status claim carries its date. When a fact is re-verified later, update the date and the source; when a fact is superseded, **remove it** rather than annotating it.
- Preserve the confidence labels (Verified / Reported / Assessed) on anything you add.
- Market figures vary by analyst; always record the firm alongside the number.
- New facts require a source link in the same edit. Unsourced claims do not enter this file.

## Primary sources

- OpenBot: repository and releases — github.com/ob-f/OpenBot
- ViGEmBus end-of-life: docs.nefarius.at/projects/ViGEm/End-of-Life
- KOBOTIX Real Racer: pocketables.com review (2022), gadgetoid.com review (2022), kobotix.com
- DR!FT: sturmkind.com and official event announcements (2025)
- CloudRC: store.cloudrc.com product pages
- Anki: en.wikipedia.org/wiki/Anki_(company); support.anki.bot Overdrive FAQ
- RoboMaster S1: dji.com support page; community reports (2024)
- Latency: fpvbuilder.io, UAVModel, Transitive Robotics, Raspberry Pi forums
- Retrofit precedent: instructables.com, hackster.io, robotzero.one
- Pricing: rojx.io/pricing, Alibaba/Made-in-China listings (retrieved 2026-11-07)

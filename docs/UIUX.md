# UI/UX design

**Status: minimal — the full design system is not decided yet.** Major choices (palette, typography, components, layout composition) are deliberately open until the design pass happens, planned before M2's first real screen. This file records only what is already fixed by product reality, so that nothing here gets re-litigated unknowingly.

## What is already fixed

These are constraints inherited from the product, not design preferences:

- **Landscape only, two-handed.** The phone sits in a cradle or wheel mount. Portrait shows a "rotate your phone" state. No exceptions in v1.
- **Glanceable, not readable.** The user is watching a game or an FPV feed. The UI communicates status at a glance; everything else must work by muscle memory.
- **Zero-latency local feedback.** Every input produces an instant visual response on the phone (wheel rotation, button press). Nothing ever waits for an echo from the PC.
- **Haptics are part of the UI.** Vibration is a designed channel that carries meaning — game rumble first (M3), car telemetry later. It is not decoration.
- **Connection state is the loudest element.** Bluetooth loss is the single most important thing to communicate, with a calm, obvious full-screen state and visible auto-reconnect.
- **One visual language, no theming.** Per the non-goals in [VISION.md](VISION.md): no skins, no portrait mode, no in-app store.

## Open design decisions

To be made in the design pass, before M2 UI work:

- Color system and palette (including connection-state colors)
- Typography scale and numeric readout treatment
- Component approach: custom cockpit widgets vs. adapted stock widgets
- Wheel layout composition (arc placement, throttle/brake controls, gear buttons)
- Gamepad layout composition
- Settings structure
- Feel benchmarks: which apps/games we measure ourselves against

## Interim rule

Until the design pass, no UI code beyond what M1 strictly needs (a minimal pairing/status screen whose look is intentionally temporary). Design decisions get recorded here as they are made; visual references and screenshots land in this file from M2 onward.

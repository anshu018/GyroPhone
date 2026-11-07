# Milestone specs

One spec per milestone, written **before** any code (see [AGENTS.md](../../AGENTS.md) — specs are the source of truth).

Naming: `M1-pair-as-ds4.md`, `M2-wheel.md`, `M3-feel.md` …

## Spec template

Every spec contains these sections, in this order:

1. **Goal** — one paragraph: what this milestone proves or delivers, and why it is next.
2. **Requirements** — what the implementation must do, concretely (byte maps, rates, screens, behaviors).
3. **Acceptance criteria** — the definition of done; each criterion must be objectively checkable. Mirrors the milestone in [ROADMAP.md](../ROADMAP.md).
4. **Task list** — ordered, small, one line each.
5. **Pitfalls (do not)** — known traps for this specific step, written at spec time from [RESEARCH.md](../RESEARCH.md) and prior experience, **and appended during the work** whenever a mistake or trap is discovered. Examples of what belongs here: byte-order or descriptor mistakes, platform quirks, threading errors, "we almost did X, which would have broken Y".
6. **Lessons learned** — filled in when the milestone closes: what actually happened, what the Pitfalls section missed, what the next agent must know before touching this step again.
7. **Open questions** — resolved before coding; anything unresolvable goes to the user.

## The mistake rule

A mistake discovered while working is recorded **in the same session**, in the current spec's *Pitfalls* section. If a mistake generalizes beyond this milestone (a rule that should always hold), it escalates to [CONVENTIONS.md](../../CONVENTIONS.md) → *The never-do list* instead. Recording is not optional and not retro-active at phase end — a pitfall noted two weeks late is a pitfall the next agent repeats first.

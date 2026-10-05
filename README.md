# Battle of Artheon

Battle of Artheon is a solo-first 2D fantasy strategy/RPG project built with Godot 4 and GDScript.

## Project principles

- Data-driven combat and balance.
- Core game logic is separated from UI/scenes.
- Items, abilities (ABI), effects (EFF), and balance values are resolved from reusable data definitions.
- Architecture should remain compatible with future multiplayer/server-authoritative development without making v1 unnecessarily complex.

## First vertical slice

`Character -> Equipment -> ABI -> Enemy -> Combat -> Result -> Item`

## Structure

- `core/` — platform-independent game rules and simulation.
- `data/` — balance/content definitions used by the core.
- `scenes/` — Godot scenes and presentation layer.
- `ui/` — UI scripts/components.
- `tests/` — deterministic development tests and fixtures.
- `docs/` — technical documentation and architecture decisions.

Design and balance source material is maintained separately from executable code; the repository is the source of truth for implementation.

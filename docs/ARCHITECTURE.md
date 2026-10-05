# Architecture v0.1

## Boundary

Battle of Artheon separates simulation from presentation.

```text
Input -> Godot presentation/application layer -> Core -> State update -> UI
                                             ^
                                             |
                                            Data
```

## Core rules

The `core/` layer must not depend on scene nodes, visual state, animations, input devices, or network/database calls.

Combat is event-based:
- Attack Event — delivery/action and active defence resolution.
- Damage Event — damage of a type, always processed through the matching passive defence.
- Effect Event (EFF) — timed/stateful effect which can create later events.

Passive numeric characteristics aggregate. Active actions and reactions resolve as independent events.

## Data-driven rule

Values expected to change during balancing belong in `data/`, not in combat algorithms. This includes curves, coefficients, caps, rarity/power tables and progression values.

## Item architecture

```text
Template + Generation Pool + Modifier identities/ranks -> Item Instance
Current Balance Tables + Item Instance -> Resolved Item
```

Instances should not permanently copy balance values that must change retroactively.

## ABI architecture

```text
Item-provided Base ABI + applicable ABI Modifiers -> Resolved ABI -> Combat Engine
```

ABI uses existing combat primitives rather than a parallel combat system.

## First milestone

Build a deterministic vertical slice:

`Character -> Equipment -> ABI -> Enemy -> Combat -> Result -> Item`

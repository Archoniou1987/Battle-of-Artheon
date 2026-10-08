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

## Map geometry and migration boundary (October 2026)

- **Gameplay map:** `TacticalMapState`, `HexGrid`, and `HexPathfinder` use axial hex coordinates (`Vector2i(q, r)`). A rectangular width/height describes the **extent of valid axial cells**, not square tiles.
- **Legacy compatibility:** `SquareMapState`, `SquareGrid`, and `SquarePathfinder` retain four-direction square semantics for existing map/encounter regression scenarios. They are not the geometry for new gameplay features.
- `MapNpcBridge` accepts either map implementation through its shared `place_entity`, `entities_at`, and `remove_entity` interface. Preserve this compatibility until legacy callers have migrated.
- New movement, patrol, encounter and visualization features should target the hex map. Do not silently replace square neighbor/distance rules inside existing tests: migrate callers and expectations explicitly.
- Hex movement cost comes from the **destination cell**. The pathfinder must choose the minimum-cost passable route, including when terrain costs are below 1.0; blocked start and goal cells are rejected.

## Technical debt to resolve before a playable vertical slice

1. Audit remaining square-map callers and migrate gameplay flows without removing regression coverage.
2. Persist and restore a unified hex gameplay session (player position, NPC state, exploration, and loot).
3. Connect the debug map presentation to the actual expedition and combat session rather than independent demo data.
4. Keep the core simulation independent from Godot scene/UI nodes.

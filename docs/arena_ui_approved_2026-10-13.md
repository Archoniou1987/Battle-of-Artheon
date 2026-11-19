# Battle of Artheon — Arena UI approved layout (2026-10-13)

Implementation contract for `ui/arena/arena_screen.gd`:

- Square combat panel; avoid separate central battlefield scene.
- Fighter header: `Name [level]`, compact fantasy serif if legible on mobile. No separate level, creature type or "Lv." line. Full details in fighter popup.
- One red HP bar below each fighter name, numeric `current / maximum` only, no HP prefix.
- Resource cluster near ABI: player Mana + AP to its left, opponent Mana + AP to its right.
- Mana remains independent of AP; melee characters may use mana-cost ABI granted by chest equipment.
- Mana bar blue, numeric current/max. AP amber and segmented, exactly one segment per point. Base max 5, hard maximum 8 including modifiers. Display only max available segments, spent points darkened.
- UI reads resources from gameplay snapshots; do not add resource mechanics or fake regeneration to ArenaScreen.
- ABI buttons should be slightly smaller, centered with spacing from zone controls and end-round button; end-round button a little lower. Avoid selection-highlight overlaps.
- Combat zone icons: do not change icon scale solely to adjust spacing. Check atlas crop against source grid; no 1px clipped frames, red artifact on defense, or black overlay on attack.
- Buff/debuff rows anchor to elixir row: horizontal alignment matches elixirs, nearest row 3–4 px above them; not to avatar portrait.
- Preserve separate popup for detailed fighter statistics.
- Validate mobile and desktop layout and CI before marking implementation complete.

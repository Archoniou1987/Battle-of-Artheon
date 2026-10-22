# Battle of Artheon — Solo Combat Screen architecture (2026-10-22)

## Decision

The existing \`ArenaScreen\` and \`ArenaCombatSession\` remain a **training / balance test stand**. Their established dark-fantasy presentation is the visual reference, not the live fight controller. Do not embed the Arena owner in the map or introduce a second combat engine.

The production expedition now presents a separate \`SoloCombatScreen\` from \`ui/arena/solo_combat_screen.gd\` over the map. This is a **UI-only view + command composer**. Its two external signals are:

- \`round_requested(orders: Dictionary)\` — complete player order, including physical target zones, manual defence, chosen ABI and chosen elixir, or an empty dictionary for terminal confirmation.
- \`elixir_selected(slot: int)\` — request read-only recalculation of ABI availability in case the elixir restores mana.

The only gameplay owner remains \`SoloLiveNpcCombat\` / \`GroupCombatSimulator\`. \`scenes/main/solo_live_map.gd\` bridges \`combat_view()\` into an explicitly display-only snapshot, then calls \`live_combat.play_round(orders)\`. There is no separate resource debit, RNG, ability cast, EFF tick, checkpoint or settlement in the UI. \`ArenaCombatLog\` remains a shared read-only renderer of canonical CombatEvents.

## Visual system

- Arena-inspired dark-blue cards and warm typography, fighter avatars, HP/MP numeric overlays, AP readout, 10 real item slots via existing \`ItemIcon\`/rarity frames.
- One hero card and separate NPC cards for an arbitrary live cohort. Only the authoritative \`controls.target_id\` is marked; tapping another NPC does not fabricate retargeting.
- Five red physical-attack body buttons and five blue manual-defence body buttons using existing zone atlas. One chosen attack zone repeats for every hit; a second chosen zone splits the first and subsequent hits. Two UI-selected zones are a presentation convenience, not a cap on canonical hit count.
- Five ABI buttons (3 weapon, chest, head); one tentative ABI selection per round.
- Four elixir quickslots; selecting one can update mana-dependent ABI button availability through \`GroupCombatSimulator.player_controls(player_id, selected_elixir)\`, without consuming charges.
- Disclosed BUFF/DEBUFF mini rows overlay the lower-left avatar corner. The separate Journal tab shows the last canonical round. The enemy uses the repository’s anonymous `wanderer_01.svg` portrait as a presentation placeholder until disclosed NPC-specific portrait resources exist.
- The game has three tabs: **Поединок** (Face to Face square plus scrollable controls), **Участники** (two roster columns: Союзники / Противники), **Журнал**. Portrait places actions below the square; landscape places actions alongside it. The single main round button stays outside these tabs and is the only control that submits orders.
- Finished but uncommitted checkpoint still allows terminal confirmation, sending \`{}\` to the existing recovery/settlement path.

## Compatibility / safeguards

- Existing \`SoloLiveNpcCombat.start/resume/play_round\`, \`GroupCombatCheckpointService\`, elixir journal, manifest, atomic victory and defeat settlement, and end-round death ordering are unchanged.
- \`SoloCombatScreen\` never creates \`ArenaCombatSession\`, \`CombatEngine\` or \`CombatState\`.
- The old Solo diagnostic controls remain **temporarily mounted behind the hidden map** to preserve existing development test contracts while the first new-screen batch is validated. They are not player-visible or the source of submitted gameplay orders. Delete them and rewrite old-only tests in a subsequent cleanup batch after first green CI.
- Real character stats, item ownership, NPC status and attack targets come exclusively from the canonical snapshot and repository.
- Avoid asserting accurate final mobile visual polish before Godot screenshot inspection.

## Verification pending

No CI was started by the assistant. The manual ABI Branch Tests now includes \`tests/ui/solo_combat_screen_runner.gd\` for UI commands, multi-NPC composition, stun, terminal confirmation and both orientations. The separate manual Solo Visual Audit captures the actual \`SoloCombatScreen\` using a clearly labelled synthetic 2-NPC fixture in 390×844 and 844×390 viewports.

**Known next refinements:** full texture icons for ABI/elixirs/effects instead of transitional symbols/IDs; actual NPC-specific portraits rather than the anonymous placeholder; richer multi-enemy targeting UX if the backend adds selectable targets; smaller-screen touch dimensions and responsive screenshots; remove technical UI dead code after CI. No gameplay math should be changed to fix presentation.


## Post-CI visual audit (Oct 22, 2026)

Both original checks passed at `294e1df7efbe667592dad18761e304b530043da7`:
- [ABI Branch Tests #39761530040](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/39761530040)
- [Solo Visual Audit #39767725662](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/39767725662), artifact `solo-visual-portrait-landscape` ID `12420678416`.

**Actual PNGs inspected:** `portrait_00.png` (390×844), `landscape_00.png` (844×390). These are real Godot scene captures with **fixture**, not player-save gameplay. In both orientations the game surface renders, shows two NPCs and the separated fighter/actions columns; the footer action remains anchored. Main issues seen were tiny text and touch controls, substantial unused lower space, and all 10 displayed equipment cells appearing blank even though the fixture provided helmet/sword artwork.

**Confirmed root cause:** `_fighter_card()` calls `ItemIcon.set_item()` before the detached card is inserted into a live scene tree. `ItemIcon._ready()` later resets the item to empty. The UI now defers item binding until after `_ready()`, without touching ownership or equipment. The new UI test verifies the first item's retained instance ID and actual texture.

**Size adjustment:** `project.godot` retains the shared 720×720 canvas-items stretch configuration, so 48–53 logical pixel buttons shrink to roughly 26–29 physical pixels in a 390px viewport. The new screen increases font sizes and control minima (attack / defense 84×83, ABI 84×80, potion 90×79, End Round 238×82 logical) without globally changing the existing Arena/Inventory/game scene scaling. After fresh captures, visually inspect clipping and ensure the minimum physical touch targets are appropriate. No exact final art or touch usability is claimed before new CI and PNG inspection.

**Validation status:** these subsequent adjustments are committed but **not yet verified**; no CI triggered automatically. The next manual batch should run ABI Branch Tests then Solo Visual Audit on the new SHA, not independently rerun tests per small UI edit.

## Face to Face correction (2026-10-22)

The user rejected the interim vertical list of fighter cards as the wrong **primary** battle visual. Its good ABI/Solo checks only meant the implementation rendered and commands remained healthy, not that the UX met the visual target. The UI was therefore reorganized: a **single 1:1 Face to Face square** uses two 232px fighter positions modelled after training Arena, and all extra combatants are in a **separate two-column participant tab**, not appended into the live duel view. The Ally column currently includes the solo player only, since `SoloLiveNpcCombat.combat_view()` currently exposes just the player and opponents; it may render additional allies in future only if an authoritative snapshot supplies them. Enemy list is fully read-only and cannot retarget combat through list taps.

The same synthetic-fixture Solo Visual Audit now captures both the duel square and the participants tab in portrait and landscape. ABI test checks the single-two-fighter invariant even with two NPCs, and rosters stay separate. This correction is not CI-verified as of this note.

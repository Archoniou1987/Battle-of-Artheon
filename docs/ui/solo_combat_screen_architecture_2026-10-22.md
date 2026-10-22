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
- Disclosed BUFF/DEBUFF mini rows overlay the lower-left avatar corner; compact log shows the last canonical round.
- Portrait stacks fighters then actions; landscape uses two columns. The main round button remains outside the scrolling body and is the only action that submits the orders.
- Finished but uncommitted checkpoint still allows terminal confirmation, sending \`{}\` to the existing recovery/settlement path.

## Compatibility / safeguards

- Existing \`SoloLiveNpcCombat.start/resume/play_round\`, \`GroupCombatCheckpointService\`, elixir journal, manifest, atomic victory and defeat settlement, and end-round death ordering are unchanged.
- \`SoloCombatScreen\` never creates \`ArenaCombatSession\`, \`CombatEngine\` or \`CombatState\`.
- The old Solo diagnostic controls remain **temporarily mounted behind the hidden map** to preserve existing development test contracts while the first new-screen batch is validated. They are not player-visible or the source of submitted gameplay orders. Delete them and rewrite old-only tests in a subsequent cleanup batch after first green CI.
- Real character stats, item ownership, NPC status and attack targets come exclusively from the canonical snapshot and repository.
- Avoid asserting accurate final mobile visual polish before Godot screenshot inspection.

## Verification pending

No CI was started by the assistant. The manual ABI Branch Tests now includes \`tests/ui/solo_combat_screen_runner.gd\` for UI commands, multi-NPC composition, stun, terminal confirmation and both orientations. The separate manual Solo Visual Audit captures the actual \`SoloCombatScreen\` using a clearly labelled synthetic 2-NPC fixture in 390×844 and 844×390 viewports.

**Known next refinements:** full texture icons for ABI/elixirs/effects instead of transitional symbols/IDs; accurate NPC portraits; richer multi-enemy targeting UX if the backend adds selectable targets; smaller-screen touch dimensions and responsive screenshots; remove technical UI dead code after CI. No gameplay math should be changed to fix presentation.

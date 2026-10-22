# Solo live elixir execution and crash recovery — 2026-10-22

## Baseline
ABI #310 (SHA `f62c01a3fee3190787d38e1bd3ef6093d9986ada`) passed before this implementation. **The writable elixir package has not yet passed CI.**

## One combat event journal, not another mutable save

`CombatElixirService.use` is the existing authoritative effect and charge service. Solo now optionally selects **one equipped elixir slot per submitted round**, alongside the existing manual attack zones, PAR073 manual defence zones and an ABI. During the canonical `GroupCombatSimulator.run_round` it validates the entire order before starting a round, starts the round, executes the selected elixir through the existing service before locking physical and ABI events, then commits the complete resolved round to `GroupCombatCheckpointService`.

Elixir consumption creates one or more canonical `CombatEvent.Kind.EFFECT` events, marked with `source_type="elixir"`, `source_instance_id`, source, target and round. All event payloads/results are already stored under the existing checkpoint SHA-256 envelope. **No new item registry or mutable secondary journal is introduced.**

`SoloCombatElixirJournal` is a pure read/reconcile adapter. It groups all potion component EFFECT events for an item within the same round as one use, enforces one potion per round and the item-defined **shared cooldown across all four slots**, checks slot ownership and charge limits, then derives spent charges and future cooldown entirely from saved events.

## Persistence boundaries

- During an unfinished fight: in-memory `ItemRepository` charges decrease immediately; the ordinary `ExpeditionSaveService` revision remains pinned to precombat inventory by the manifest. The combat checkpoint safely preserves every resolved use.
- At restart: resume reconstructs the same `GroupCombatSimulator` and journal from checkpoint; `SoloCombatElixirJournal.apply_to_baseline` copies the original expedition repository and deducts only checkpointed uses. It binds that charge-correct repository to the resumed owner; never replays the effect events, rerolls combat or touches the baseline save.
- At victory: the live, charge-mutated repository must match the checkpoint-derived repository from the pinned base expedition **before NPC settlement or loot generation**. The existing atomic victory world snapshot contains spent charges.
- At defeat: terminal loss staging reads the original expedition, derives charge deductions using the finalized checkpoint, then writes them with the full-health retreat snapshot. Recovery independently verifies that the staged repository matches exactly those derived charges, not the original precombat repository.
- Repeated recovery remains idempotent: the existing victory/defeat publication markers and receipt rules prevent a second item debit.

## UI and scope

The Solo map now displays four belt slots and charges and offers `Без эликсира` or one unlocked, valid slot in its action form. Selection is disabled while depleted, locked, during a shared cooldown or after battle. The elixir resolves together with attack, defence and one ABI in that submitted round; this implementation does **not** yet add Arena's separate immediately-on-press Mind Game interaction or round-phase checkpoint for early press.

This package does not alter the globally shared five-second `GroundLootService` duration; Solo ground pickup remains 2 seconds.

## Regression

`tests/map/solo_live_elixir_round_runner.gd` runs a real mapped NPC fight with a real belt, two assigned potions, one consumable in round 1 and a recovery from the exact checkpoint. It proves the source expedition still contains precombat charges until settlement, only one charge is charged in the live repository, canonical elixir EFFECT events survive the restart without replay, attempted use of a different slot on cooldown does not start a round, and a no-elixir second round causes no extra deduction. It runs inside the existing ABI workflow along with all previous PAR/ABI/EFF/group checkpoint/defeat/ground loot runners.

The checkpoint-derived journal now also validates each actual EFFECT payload against the elixir's authored component kind and values, not only component count. A forged heal value, unrelated effect ID, or duplicate component must fail closed. The regression temporarily corrupts one resolved heal event in memory, verifies rejection, then restores it without changing the durable checkpoint.

### Known follow-up
The normal ABI availability readout currently preflights mana before elixir recovery. Therefore a player starting with insufficient mana cannot yet select an otherwise valid ABI funded by a mana elixir **in the same submitted round**. This combined-action edge case needs a separate preflight adjustment and test; do not mark it complete. Also, the final CI workflow must verify compilation and the existing victory/defeat regressions.

Do not claim this package is green until the user performs the ABI run.

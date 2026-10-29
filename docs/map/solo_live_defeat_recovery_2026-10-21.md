# Solo live NPC defeat — durable terminal retreat and restart (2026-10-21)

Previous confirmed green: **ABI #303**, run `39682339473`, SHA `29dcee1e3099c5b79768764f4d13ba031fa7babc`.

**This new defeat package is not yet verified by ABI.**

## Semantics for the current first playable Solo map

- A genuinely finalised player death (or draw where the player died) is a **defeat**, not a victory. The battle must first persist its completed round checkpoint.
- The player retreats to the **saved expedition starting cell**; newly launched expeditions record this under `ExpeditionState.SOLO_START_CELL_KEY`. For older saves without that field, the last authoritative pre-battle position is the safe fallback.
- The player is restored to full HP and mana in this **provisional v1 defeat policy** to avoid an immediately unusable map. This is a gameplay-balancing rule, not part of combat arithmetic; revisit together with future defeat penalties. No experience, equipment or item penalty has been introduced.
- Enemy NPCs **remain alive**, with no victory tombstone, loot pool, ground reward, or inventory grant.
- The canonical expedition inventory, already obtained loot, NPC kills from **previous** victories, and all unrelated world state remain unchanged.
- Defeats have a separate ledger `solo_combat_defeats_v1`, not the victory ledger `committed_combat_outcomes`.
- Re-fighting the same still-living NPC is allowed. A new encounter attempt gets a distinct checkpoint/terminal key (`:attempt_2`, etc.) so the first terminal save cannot be mistaken for the second encounter.

## Crash-safe durability

1. `SoloCombatSessionManifest` is written before NPC contact, as for a winning fight.
2. `GroupCombatSimulator` must finish and durably checkpoint the decisive losing round.
3. `SoloCombatDefeatService.stage` confirms the terminal player death from the **persisted** checkpoint and compares its roster, round and encounter identity to the live simulator.
4. Only then does it stage a **verified full ExpeditionSaveService snapshot** at the manifest's terminal path: starting position, revived character and an immutable defeat record with checkpoint hash, roster fingerprint, round and precombat expedition revision.
5. `SoloCombatSessionManifest.recover_on_launch` distinguishes the terminal's actual format:
   - `BOA_MAP_WORLD_COMMIT_V1`: existing victory receipt flow.
   - `BOA_SOLO_EXPEDITION_SAVE_V1`: defeat flow.
   Unknown/corrupt formats are rejected.
6. `SoloCombatDefeatService.recover` verifies the saved checkpoint, previous revision and **all unrelated owners/ledgers/items**, then publishes the staged snapshot atomically into the canonical expedition save.
7. If the canonical defeat marker is already present and matches the staged record, recovery returns `already_published=true` without a second save.
8. After successful publication, the manifest is cleared. Old attempt-specific checkpoints remain isolated from future attempts; manual garbage collection can be added later.

A missing/corrupt checkpoint, stale expedition revision, mismatched owner or unrelated world mutation **blocks** publication and does not trigger a new battle or reward.

## CI coverage

`tests/map/solo_live_defeat_resume_runner.gd` tests a real group combat defeat from a wounded level-1 player, restart from terminal checkpoint without replay, no NPC tombstones/rewards, preserved inventory, retreat to recorded origin, idempotent replay, distinct second encounter, and crash/relaunch publication of the second defeat.

The existing victory, checkpoint and town/map tests continue to run as part of the same ABI job.

## Still outside this package

- Dedicated defeat animation/popup, equipment durability penalty and broader death consequences.
- Manual combat targeting, abilities, blocks and consumables in this early map screen.
- Garbage collection of old **published** combat artifacts.

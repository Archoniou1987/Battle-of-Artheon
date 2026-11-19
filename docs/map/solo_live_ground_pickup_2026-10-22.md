# Solo live map — two-second ground pickup (2026-10-22)

Prior verified baseline: ABI #305 (SHA `6139e83d4feab35706e6aaf980622092b3137254`). This pickup batch needs a new ABI run.

## Behavior
- On the active Solo map, the current cell shows its accessible unclaimed ground item instances with "Подобрать" buttons.
- Tapping an item creates an ephemeral pickup ticket and blocks map movement, entering combat and returning to town for **2 seconds**.
- After the timer, the same ticket is completed and the exact existing item instance moves from the expedition ground registry into the player's inventory, followed by a verified, atomic `ExpeditionSaveService.save`.
- On save failure both the ground registry and inventory are restored. Neither a new loot roll nor a new repository item is created.
- A restart drops in-flight tickets. Cancelled/used tickets cannot be completed. A move before completion invalidates a ticket.
- Combat manifests lock all pickup operations. Visible loot remains authoritative in the expedition state across reloads.
- The generic `GroundLootService` still defaults to **5 seconds** for all other callers. Solo passes a duration of 2 seconds explicitly, not by mutating the shared constant.

## Test
`tests/map/solo_live_ground_pickup_runner.gd`: real Solo save/map, persisted world loot before pickup, precise two-second deadline, early attempt rejection, restart/cancel/movement invalidation, single transfer of a preserved durability-bearing instance, no duplicate claim, durable ownership after reload, non-Solo default of five seconds.

Workflow: `.github/workflows/abi-branch-tests.yml`.

Not in scope: final item art, progress-bar polish, gamewide time balancing.

# First persistent NPC placements on live Solo map — 2026-10-21

Verified prior baseline: ABI #296, run 39670781488, success at 6b1940e50e9459a0d5c272531ef26d3649f3fa4d.

The playable Solo map now opens a shared MapNpcBridge with NPC001 Wolf, NPC003 Bandit, and NPC004 Archer from the existing starting-region catalog. All three have deterministic instance IDs and cells; opening the same expedition again recreates the same NPC ownership and locations. NPCs whose IDs occur in a committed defeat tombstone are not recreated.

The map UI marks nearby enemies with ⚔ inside the current three-hex view. On a player attempt to enter any enemy cell, SoloLiveMapSession.move_one_step explicitly returns combat_ui_not_connected BEFORE mutating map position, expedition save or inventory. The transition remains fail-closed until the genuine combat UI, terminal checkpoint and settlement chain can run end to end. This is intentional and is NOT an NPC battle implementation.

The existing early ABI live-map runner now validates deterministic enemy reconstruction and enemy contact not mutating the durable player position, in addition to its city-map-city flow. NPCs are static for this first milestone: patrols, aggression, combat dispatch and procedural themed-region generation remain unconnected.

New changes are awaiting ABI verification.

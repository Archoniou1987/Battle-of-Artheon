# Canonical town snapshot after a Solo expedition — 2026-10-21

Verified baseline: ABI #292 (39657428730), success at
f12ddd36b58f56d2aa043ab80d5fffaf4dc9b362.

## Problem

The village currently persists progression and inventory in separate
legacy files, while a Solo expedition uses one atomic save. Writing
both city files on return risks crash-time partial updates and stale
inventory resurrecting item instances.

## Added boundary

`SoloTownSaveService` provides one versioned, hashed and verified
`user://` snapshot containing full character and repository data.
It uses a temporary file, a round-trip restoration check, then an
atomic replace. Existing-town writes require the current content
SHA-256, blocking stale writers.

`adopt_closed_expedition` reads ONLY a verified, closed
`SoloTownReturnService` owner. It writes a return-source receipt
(expedition ID and full saved-expedition SHA-256) alongside that
character and an ItemRepository containing ONLY owned instance IDs.
Uncollected ground drops never enter the town save. Repeating the
same transfer returns `already_adopted` and performs no writes.
A different transfer cannot silently overwrite an existing town save;
it returns `town_snapshot_conflict` pending an explicit migration
protocol.

## Coverage and limits

`tests/map/solo_town_save_adoption_runner.gd` checks closure
requirement, owned items versus ground drops, immutable legacy town
data, repeated adoption, wrong-player and stale-revision protection.
It runs early in ABI Branch Tests.

**Not yet wired into the village UI:** current `main.gd` reads/writes
legacy progression and inventory; do NOT activate both city writers
against these same items concurrently. The next step is a controlled
one-time migration (or a complete canonical city-loader/writer
switch), including crash recovery and preservation of existing local
saves. The standalone transfer works, but this package does not yet
finish playable village → map → village transitions.

New package awaits Godot CI.

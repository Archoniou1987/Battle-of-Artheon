# Town → Solo Expedition ownership bridge (2026-10-21)

## Verified baseline

Last completed CI reported as green: ABI #290, SHA
`9f995ae6d57a7ef87f5f70c34bfcb687c2c8fd96`.
The previous map-entry gate commit `b69f1ac...` is also part of the
working branch, but has not been confirmed by a later successful CI.

## The actual ownership problem

The starting village currently persists character progression and
inventory in **two separate legacy files**. A Solo expedition stores
`CharacterState`, `ItemRepository`, and `ExpeditionState` together
in one atomic file. Re-importing the town repository after the first
fight would overwrite or duplicate expedition-earned item instances.

## New safe transfer contract

`SoloTownExpeditionBridge.create_from_town(...)` creates an expedition
**only once** from the actual validated town `CharacterState` and
`ItemRepository` (including progression, equipment, elixirs and current
resources). It makes independent restored copies before writing, so
failure cannot damage the town's live state. It writes a SHA-256 town
origin fingerprint into the expedition and rejects existing expedition
saves or pending combat manifests.

`open_existing(...)` reopens the canonical saved expedition through
`SoloExpeditionLaunchGate` and never copies inventory from the town
again. This protects items collected through real map combat and ground
pickup from stale town snapshots.

`expedition_id_for_player(id)` provides the same deterministic Solo ID
to town Map navigation and future expedition creation; the town had
previously passed an empty expedition ID to the launch gate.

`town_matches_origin(...)` can detect when town state has diverged
from the expedition's original handoff snapshot. It does NOT silently
merge or write two legacy town files.

## CI coverage and remaining work

New early ABI runner: `tests/map/solo_town_expedition_bridge_runner.gd`.
It exercises original item ownership, no repeated creation, new
expedition-earned item preservation across reload, wrong-player
rejection, original town immutability, and blocking creation with a
pending combat manifest.

This package DOES NOT yet offer a usable map scene, transfer earned
items back into persistent village data, or create expedition saves
from the town UI. Those require a coordinated town exit/return
transaction and generated map/NPC reconciliation; directly exposing
them now could duplicate equipment. New changes await CI.

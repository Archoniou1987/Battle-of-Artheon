class_name MapCombatSettlementService
extends RefCounted

## Durable world-outcome journal for one terminal map/group encounter.
## This journal is intentionally separate from the round checkpoint, Arena,
## CharacterState and the eventual expedition/inventory save containers.
##
## Phase 1: stage() verifies a disk-committed terminal battle and records the
##         exact rolled reward ONCE, before mutating any NPC or world object.
## Phase 2: apply() replays that receipt idempotently to the current map,
##         ExpeditionState and ItemRepository (including after process death).
## Phase 3: external world/inventory persistence and acknowledgement will
##         delete this receipt plus its battle checkpoint in a later package.
##
## Never discard this journal just because an in-memory NPC is dead.
const FORMAT := "BOA_MAP_COMBAT_SETTLEMENT_V1"
const SCHEMA := 1
const DEFAULT_PATH := "user://map_combat_settlement_v1.json"
const MAX_BYTES := 1024 * 1024
const MARKER_KEY := "committed_combat_outcomes"

static func _valid_path(path: String) -> bool:
	return GroupCombatCheckpointService._valid_path(path)

static func _validate_identity(encounter_key: String, expedition_id: String, player_id: String) -> bool:
	return not encounter_key.strip_edges().is_empty() and encounter_key.length() <= 160 and not expedition_id.strip_edges().is_empty() and expedition_id.length() <= 160 and not player_id.strip_edges().is_empty() and player_id.length() <= 160

static func _validate_receipt(receipt: Dictionary, encounter_key: String, expedition_id: String, player_id: String) -> String:
	if int(receipt.get("schema",-1)) != SCHEMA or String(receipt.get("winning_team","")) != "players":
		return "invalid_receipt_version_or_winner"
	if String(receipt.get("encounter_key","")) != encounter_key or String(receipt.get("expedition_id","")) != expedition_id or String(receipt.get("player_id","")) != player_id:
		return "receipt_context_mismatch"
	if not receipt.get("npc_ids") is Array or Array(receipt["npc_ids"]).is_empty() or Array(receipt["npc_ids"]).size() > 32:
		return "invalid_receipt_roster"
	if not receipt.get("loot_pool") is Dictionary or not receipt.get("item_snapshots") is Dictionary:
		return "invalid_receipt_loot"
	if not receipt.get("npc_positions") is Dictionary:
		return "invalid_receipt_positions"
	if not receipt.get("round") is int and not receipt.get("round") is float:
		return "invalid_receipt_round"
	if int(receipt["round"]) < 1 or int(receipt["round"]) > GroupCombatCheckpointService.MAX_ROUNDS:
		return "invalid_receipt_round"
	var seen: Dictionary = {}
	for raw_id in Array(receipt["npc_ids"]):
		var id := String(raw_id)
		if id.is_empty() or seen.has(id):
			return "invalid_receipt_npc_id"
		seen[id] = true
		var position: Variant = Dictionary(receipt["npc_positions"]).get(id,null)
		if not position is Array or Array(position).size() != 2:
			return "invalid_receipt_npc_position"
	var pool: EncounterLootPool = EncounterLootPool.from_dict(Dictionary(receipt["loot_pool"]))
	var item_snapshots: Dictionary = receipt["item_snapshots"]
	if pool.item_ids().size() != Array(Dictionary(receipt["loot_pool"]).get("entries",[])).size():
		return "invalid_receipt_duplicate_loot"
	if pool.item_ids().size() > 96:
		return "receipt_too_many_items"
	for item_id in pool.item_ids():
		if not item_snapshots.has(item_id):
			return "receipt_item_missing"
		if not item_snapshots[item_id] is Dictionary or String(item_snapshots[item_id].get("instance_id","")) != item_id:
			return "receipt_invalid_item_snapshot"
		if String(pool.assigned_player_by_item.get(item_id,"")) != player_id:
			return "receipt_wrong_loot_owner"
	for raw_id in item_snapshots.keys():
		if not pool.item_ids().has(String(raw_id)):
			return "receipt_extraneous_item"
	return ""

static func _signature(receipt: Dictionary) -> String:
	return JSON.stringify(receipt).sha256_text()

static func read(path: String, encounter_key: String, expedition_id: String, player_id: String) -> Dictionary:
	if not _valid_path(path) or not _validate_identity(encounter_key,expedition_id,player_id):
		return {"ok":false,"reason":"invalid_settlement_read_context"}
	if not FileAccess.file_exists(path):
		return {"ok":false,"reason":"settlement_not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"settlement_read_failed"}
	if file.get_length() < 16 or file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"settlement_size_rejected"}
	var json_text := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(json_text)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT:
		return {"ok":false,"reason":"settlement_invalid_envelope"}
	var raw: Variant = envelope.get("receipt_json",null)
	if not raw is String or raw.is_empty() or raw.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"settlement_integrity_failed"}
	var decoded: Variant = JSON.parse_string(raw)
	if not decoded is Dictionary:
		return {"ok":false,"reason":"settlement_invalid_receipt"}
	var issue := _validate_receipt(decoded,encounter_key,expedition_id,player_id)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	return {"ok":true,"receipt":decoded,"sha256":String(envelope["sha256"])}

static func _persist(receipt: Dictionary,path: String) -> Dictionary:
	if not _valid_path(path):
		return {"ok":false,"reason":"invalid_settlement_path"}
	var raw := JSON.stringify(receipt)
	var envelope := JSON.stringify({"format":FORMAT,"receipt_json":raw,"sha256":raw.sha256_text()})
	if envelope.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok":false,"reason":"settlement_too_large"}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"settlement_temp_open_failed"}
	file.store_string(envelope)
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
	if error != OK:
		return {"ok":false,"reason":"settlement_replace_failed","error":error}
	return {"ok":true,"sha256":raw.sha256_text()}

## Validates a terminal, *disk-committed* engine outcome and freezes reward
## rolls to a durable journal before mutating world entities or loot pools.
static func stage(session: Dictionary, expedition: ExpeditionState, map, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository, loot_service: NpcPossessionLootService, quality_chances: Dictionary, encounter_key: String, receipt_path: String = DEFAULT_PATH, now_unix: int = -1) -> Dictionary:
	if expedition == null or not expedition.is_active() or player == null or repository == null or bridge == null or map == null or loot_service == null:
		return {"ok":false,"reason":"invalid_settlement_dependencies"}
	if not _valid_identity(encounter_key,expedition.expedition_id,player.character_id) or not _valid_path(receipt_path):
		return {"ok":false,"reason":"invalid_settlement_context"}
	if FileAccess.file_exists(receipt_path):
		var prior := read(receipt_path,encounter_key,expedition.expedition_id,player.character_id)
		if bool(prior.get("ok",false)):
			return {"ok":true,"already_staged":true,"receipt":prior["receipt"],"sha256":prior["sha256"]}
		# A stale or corrupt journal is never overwritten by a new battle.
		return {"ok":false,"reason":String(prior.get("reason","invalid_existing_receipt"))}
	var sim: GroupCombatSimulator = session.get("simulator") as GroupCombatSimulator
	var checkpoint_path := String(session.get("checkpoint_path",""))
	if sim == null or not _valid_path(checkpoint_path) or receipt_path == checkpoint_path:
		return {"ok":false,"reason":"missing_persisted_battle"}
	if sim.checkpoint_path != checkpoint_path or sim.checkpoint_encounter_key != encounter_key or sim.group.team_of(player.character_id) != "players":
		return {"ok":false,"reason":"settlement_battle_identity_mismatch"}
	if not sim.controller.combat_finished() or sim.controller.winning_team() != "players":
		return {"ok":false,"reason":"settlement_requires_player_victory"}
	var checkpoint := GroupCombatCheckpointService.read(checkpoint_path,encounter_key,sim.checkpoint_roster_fingerprint)
	if not bool(checkpoint.get("ok",false)) or not bool(checkpoint.get("terminal",false)):
		return {"ok":false,"reason":"missing_durable_terminal_checkpoint"}
	var disk_sim: GroupCombatSimulator = checkpoint["simulator"]
	if disk_sim.controller.winning_team() != "players" or disk_sim.state.round_number != sim.state.round_number or disk_sim.state.next_event_id != sim.state.next_event_id:
		return {"ok":false,"reason":"terminal_checkpoint_disagrees"}
	var npcs: Array[NpcInstance] = []
	var roster_ids: Array[String] = []
	var seen: Dictionary = {}
	for raw_npc in Array(session.get("npcs",[])):
		var npc := raw_npc as NpcInstance
		if npc == null or seen.has(npc.instance_id):
			return {"ok":false,"reason":"invalid_terminal_npc_roster"}
		seen[npc.instance_id] = true
		if not npc.is_alive() or not bridge.instances.has(npc.instance_id) or not map.entity_positions.has(npc.instance_id):
			return {"ok":false,"reason":"terminal_npc_already_resolved"}
		if bridge.instances[npc.instance_id] != npc:
			return {"ok":false,"reason":"terminal_npc_instance_mismatch"}
		var victim := disk_sim.state.get_combatant(npc.instance_id)
		if victim == null or not victim.is_death_finalized():
			return {"ok":false,"reason":"npc_not_finalized_in_checkpoint"}
		npcs.append(npc)
		roster_ids.append(npc.instance_id)
	if npcs.is_empty() or npcs.size() != Array(session.get("npc_instance_ids",[])).size():
		return {"ok":false,"reason":"terminal_npc_roster_mismatch"}
	for raw_id in session.get("npc_instance_ids",[]):
		if not seen.has(String(raw_id)):
			return {"ok":false,"reason":"terminal_npc_roster_mismatch"}
	if disk_sim.state.combatants.size() != npcs.size() + 1:
		return {"ok":false,"reason":"unexpected_combat_participants"}
	var markers: Dictionary = Dictionary(expedition.world_state.get(MARKER_KEY,{}))
	if markers.has(encounter_key):
		return {"ok":false,"reason":"settlement_already_recorded"}
	var positions: Dictionary = {}
	var pool := EncounterLootPool.new()
	var item_snapshots: Dictionary = {}
	for npc in npcs:
		var pos: Vector2i = map.entity_positions[npc.instance_id]
		positions[npc.instance_id] = [pos.x,pos.y]
		for raw_drop in loot_service.roll_drops(npc,repository,quality_chances):
			if not raw_drop is Dictionary:
				continue
			var item_id := String(raw_drop.get("instance_id",""))
			if item_id.is_empty() or not pool.add_drop(item_id,npc.instance_id):
				return {"ok":false,"reason":"invalid_or_duplicate_reward"}
			var stored := repository.get_item(item_id)
			if stored.is_empty():
				return {"ok":false,"reason":"reward_item_missing"}
			item_snapshots[item_id] = stored.duplicate(true)
	pool.assign_all(player.character_id)
	var combat_cell: Vector2i = map.entity_positions[npcs[0].instance_id]
	if session.has("combat_cell") and session["combat_cell"] is Vector2i:
		combat_cell = session["combat_cell"]
	var effective_time := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	pool.place_on_hex(combat_cell,effective_time)
	roster_ids.sort()
	var receipt: Dictionary = {
		"schema":SCHEMA,"encounter_key":encounter_key,"expedition_id":expedition.expedition_id,
		"player_id":player.character_id,"winning_team":"players",
		"round":sim.state.round_number,"npc_ids":roster_ids,
		"npc_positions":positions,"loot_pool":pool.to_dict(),
		"item_snapshots":item_snapshots
	}
	var issue := _validate_receipt(receipt,encounter_key,expedition.expedition_id,player.character_id)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	var stored: Dictionary = _persist(receipt,receipt_path)
	if not bool(stored.get("ok",false)):
		return stored
	return {"ok":true,"already_staged":false,"receipt":receipt,"sha256":stored["sha256"]}

## Replay is safe both if the process crashed before any world mutation and
## if it crashed after NPC death or a partially applied world update.
## The expedition's saved ledger marker suppresses loot resurrection after a
## claim/expiry, while NPCs are still re-killed on regenerated maps.
static func apply(receipt_path: String, encounter_key: String, expedition: ExpeditionState, map, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository) -> Dictionary:
	if expedition == null or map == null or bridge == null or player == null or repository == null:
		return {"ok":false,"reason":"invalid_replay_dependencies"}
	var loaded := read(receipt_path,encounter_key,expedition.expedition_id,player.character_id)
	if not bool(loaded.get("ok",false)):
		return loaded
	var receipt: Dictionary = loaded["receipt"]
	var marker_hash := String(loaded["sha256"])
	var markers: Dictionary = Dictionary(expedition.world_state.get(MARKER_KEY,{})).duplicate(true)
	if markers.has(encounter_key) and String(markers[encounter_key]) != marker_hash:
		return {"ok":false,"reason":"conflicting_settlement_marker"}
	var already_applied := markers.has(encounter_key)
	var ids: Array = receipt["npc_ids"]
	var locations: Dictionary = receipt["npc_positions"]
	# Prevalidate the whole cohort before mutation; no partial death on
	# missing/cross-expedition NPCs or moved ID collisions.
	for raw_id in ids:
		var id := String(raw_id)
		if not bridge.instances.has(id):
			return {"ok":false,"reason":"missing_receipt_npc","npc_id":id}
		var npc: NpcInstance = bridge.instances[id]
		if npc == null:
			return {"ok":false,"reason":"invalid_receipt_npc","npc_id":id}
		if npc.is_alive():
			if not map.entity_positions.has(id):
				return {"ok":false,"reason":"npc_not_on_map","npc_id":id}
			var pos: Vector2i = map.entity_positions[id]
			var raw_pos: Array = locations[id]
			if pos != Vector2i(int(raw_pos[0]),int(raw_pos[1])):
				return {"ok":false,"reason":"npc_world_location_mismatch","npc_id":id}
		elif map.entity_positions.has(id):
			return {"ok":false,"reason":"dead_npc_still_on_map","npc_id":id}
	var pool := EncounterLootPool.from_dict(receipt["loot_pool"])
	# The persisted expedition ledger is authoritative after a successful
	# apply. Do NOT resurrect items which have already been claimed/expired.
	# Only recover repository instances for loot still awaiting a claim.
	var pending_pool: EncounterLootPool = expedition.restore_loot_pool(encounter_key) if already_applied else pool
	if pending_pool != null:
		for item_id in pending_pool.item_ids():
			if not pool.item_ids().has(item_id):
				return {"ok":false,"reason":"unrecognized_persisted_reward","item_id":item_id}
			if repository.has_item(item_id):
				# Never overwrite existing item condition or ownership.
				continue
			var stored: Dictionary = Dictionary(receipt["item_snapshots"][item_id])
			if not repository.add_item(stored):
				return {"ok":false,"reason":"receipt_item_restore_failed","item_id":item_id}
	for raw_id in ids:
		var id := String(raw_id)
		var npc: NpcInstance = bridge.instances[id]
		if npc.is_alive() and not bridge.resolve_death(map,id):
			return {"ok":false,"reason":"receipt_npc_death_failed","npc_id":id}
	if not already_applied:
		# Do NOT recreate rewards if the expedition already recorded this
		# outcome: its original loot may have been claimed or expired.
		if not expedition.save_loot_pool(encounter_key,pool):
			return {"ok":false,"reason":"receipt_loot_commit_failed"}
		markers[encounter_key] = marker_hash
		expedition.world_state[MARKER_KEY] = markers
	return {"ok":true,"already_applied":already_applied,"defeated_ids":ids.duplicate(),"loot_pool":expedition.restore_loot_pool(encounter_key),"needs_world_save":true}

static func settle(session: Dictionary, expedition: ExpeditionState, map, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository, loot_service: NpcPossessionLootService, quality_chances: Dictionary, encounter_key: String, receipt_path: String = DEFAULT_PATH, now_unix: int = -1) -> Dictionary:
	var staged := stage(session,expedition,map,bridge,player,repository,loot_service,quality_chances,encounter_key,receipt_path,now_unix)
	if not bool(staged.get("ok",false)):
		return staged
	var result := apply(receipt_path,encounter_key,expedition,map,bridge,player,repository)
	result["already_staged"] = bool(staged.get("already_staged",false))
	return result

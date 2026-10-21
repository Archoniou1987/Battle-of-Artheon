class_name MapWorldCommitService
extends RefCounted

## Opt-in, single-encounter atomic snapshot for the durable combat outcome.
## The snapshot owns the expedition ledger, live ItemRepository, complete
## inventory/equipment, character progression and current HP/mana together.
## It is NOT a replacement for the city's legacy progression/inventory files;
## map-scene startup must restore this snapshot before allowing map actions.
const FORMAT := "BOA_MAP_WORLD_COMMIT_V1"
const VERSION := 1
const DEFAULT_PATH := "user://map_world_commit_v1.json"
const MAX_BYTES := 8 * 1024 * 1024
const TOMBSTONES_KEY := "completed_combat_npc_cohorts"

static func _valid_path(path: String) -> bool:
	return GroupCombatCheckpointService._valid_path(path)

static func _valid_id(id: String) -> bool:
	return not id.strip_edges().is_empty() and id.length() <= 160

static func _read_envelope(path: String) -> Dictionary:
	if not _valid_path(path):
		return {"ok":false,"reason":"invalid_world_snapshot_path"}
	if not FileAccess.file_exists(path):
		return {"ok":false,"reason":"world_snapshot_not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"world_snapshot_read_failed"}
	if file.get_length() < 16 or file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"world_snapshot_invalid_size"}
	var content := file.get_as_text()
	file.close()
	var envelope: Variant = JSON.parse_string(content)
	if not envelope is Dictionary or String(envelope.get("format","")) != FORMAT:
		return {"ok":false,"reason":"world_snapshot_invalid_envelope"}
	var raw: Variant = envelope.get("payload_json",null)
	if not raw is String or raw.is_empty() or raw.sha256_text() != String(envelope.get("sha256","")):
		return {"ok":false,"reason":"world_snapshot_integrity_failed"}
	var decoded: Variant = JSON.parse_string(raw)
	if not decoded is Dictionary:
		return {"ok":false,"reason":"world_snapshot_invalid_payload"}
	return {"ok":true,"payload":decoded,"hash":String(envelope["sha256"])}

static func _restore_character(saved: Dictionary, repository: ItemRepository) -> Dictionary:
	for key in ["id","name","progression","resources","inventory","equipment","elixirs","traits"]:
		if not saved.has(key):
			return {"ok":false,"reason":"world_character_missing_" + key}
	if not saved["id"] is String or not _valid_id(String(saved["id"])) or not saved["name"] is String:
		return {"ok":false,"reason":"invalid_world_character_identity"}
	if not saved["progression"] is Dictionary or not saved["resources"] is Dictionary or not saved["inventory"] is Dictionary or not saved["equipment"] is Dictionary or not saved["elixirs"] is Array or not saved["traits"] is Array:
		return {"ok":false,"reason":"invalid_world_character_shape"}
	var character := CharacterState.new(String(saved["id"]),String(saved["name"]),1)
	if not character.restore_progression(saved["progression"]) or not character.restore_resources(saved["resources"]):
		return {"ok":false,"reason":"world_character_progression_or_resources_rejected"}
	var inventory_data: Dictionary = saved["inventory"]
	if String(inventory_data.get("owner_id","")) != character.character_id or not inventory_data.get("instance_ids") is Array:
		return {"ok":false,"reason":"world_inventory_owner_mismatch"}
	character.inventory = InventoryState.from_dict(inventory_data,repository)
	if character.inventory.size() != Array(inventory_data["instance_ids"]).size():
		return {"ok":false,"reason":"world_inventory_instance_missing_or_duplicate"}
	var slots: Dictionary = saved["equipment"]
	var equipment := EquipmentState.new()
	if slots.size() != equipment.slots.size():
		return {"ok":false,"reason":"world_equipment_slot_count"}
	for slot in equipment.slots.keys():
		if not slots.has(slot):
			return {"ok":false,"reason":"world_equipment_slot_missing"}
		var item_id: Variant = slots[slot]
		if item_id != null and (not item_id is String or not character.inventory.owns(String(item_id))):
			return {"ok":false,"reason":"world_equipment_item_missing"}
		equipment.slots[slot] = item_id
	# Duplicate slots are permitted only when the item actually occupies all
	# of those slots (two-handed / set usage), matching the main inventory loader.
	for item_id in character.inventory.instance_ids():
		var occupied: Array = []
		for slot in equipment.slots:
			if equipment.slots[slot] == item_id:
				occupied.append(slot)
		if occupied.is_empty():
			continue
		var item := repository.get_item(String(item_id))
		var allowed: Array = item.get("equip_slots",[])
		var usage: Array = item.get("slot_usage",[occupied[0]])
		if occupied.size() == 1 and usage.size() == 1:
			var target: String = String(occupied[0])
			var opposite := "ring1" if target == "ring2" else "ring2"
			if ["ring1","ring2"].has(target) and allowed.has(opposite) and not allowed.has(target) and usage[0] == opposite:
				allowed = allowed.duplicate()
				allowed.append(target)
				usage = [target]
		if not allowed.has(occupied[0]) or usage.size() != occupied.size():
			return {"ok":false,"reason":"world_equipment_occupancy_mismatch"}
		for slot in usage:
			if not occupied.has(slot):
				return {"ok":false,"reason":"world_equipment_usage_mismatch"}
	character.equipment = equipment
	if not character.restore_elixir_slots(saved["elixirs"],repository):
		return {"ok":false,"reason":"world_elixir_slot_invalid"}
	var traits: Array[String] = []
	for raw_trait in Array(saved["traits"]):
		if not raw_trait is String or raw_trait.is_empty() or traits.has(String(raw_trait)):
			return {"ok":false,"reason":"world_duplicate_trait"}
		traits.append(String(raw_trait))
	character.learned_trait_ids = traits
	if not CharacterProgression._is_whole_number(saved.get("bag_capacity",-1)):
		return {"ok":false,"reason":"world_bag_capacity_invalid"}
	character.bag_capacity = int(saved.get("bag_capacity",-1))
	return {"ok":true,"character":character}

static func _validate_tombstones(world: Dictionary, encounter_key: String, receipt_hash: String, receipt: Dictionary) -> String:
	var completed: Variant = world.get(TOMBSTONES_KEY,{})
	if not completed is Dictionary or not completed.has(encounter_key):
		return "world_missing_npc_tombstones"
	var entry: Variant = completed[encounter_key]
	if not entry is Dictionary or String(entry.get("receipt_sha256","")) != receipt_hash:
		return "world_tombstone_receipt_mismatch"
	if not entry.get("npc_ids") is Array or not entry.get("npc_positions") is Dictionary:
		return "world_tombstone_invalid_shape"
	var ids: Array = entry["npc_ids"]
	if ids.size() != Array(receipt["npc_ids"]).size() or ids.size() == 0:
		return "world_tombstone_roster_mismatch"
	var seen: Dictionary = {}
	for raw_id in ids:
		if not raw_id is String or not _valid_id(raw_id) or seen.has(raw_id):
			return "world_tombstone_id_invalid"
		seen[raw_id] = true
		if not Array(receipt["npc_ids"]).has(raw_id):
			return "world_tombstone_roster_mismatch"
		if not Dictionary(entry["npc_positions"]).has(raw_id):
			return "world_tombstone_missing_position"
		var pos: Variant = entry["npc_positions"][raw_id]
		if not pos is Array or Array(pos).size() != 2:
			return "world_tombstone_invalid_position"
		var expected: Variant = Dictionary(receipt["npc_positions"]).get(raw_id,null)
		if JSON.stringify(pos) != JSON.stringify(expected):
			return "world_tombstone_position_mismatch"
	return ""

static func _character_to_dict(player: CharacterState) -> Dictionary:
	return {
		"id":player.character_id,"name":player.display_name,
		"progression":player.progression_snapshot(),"resources":player.resources_to_dict(),
		"inventory":player.inventory.to_dict(),"equipment":player.equipment.slots.duplicate(true),
		"elixirs":player.elixir_slots.duplicate(),"traits":player.learned_trait_ids.duplicate(),
		"bag_capacity":player.bag_capacity
	}

static func read(path: String, encounter_key: String, expedition_id: String, player_id: String) -> Dictionary:
	if not _valid_id(encounter_key) or not _valid_id(expedition_id) or not _valid_id(player_id):
		return {"ok":false,"reason":"invalid_world_snapshot_identity"}
	var loaded := _read_envelope(path)
	if not bool(loaded.get("ok",false)):
		return loaded
	var payload: Dictionary = loaded["payload"]
	if int(payload.get("version",-1)) != VERSION:
		return {"ok":false,"reason":"world_snapshot_version_mismatch"}
	if String(payload.get("encounter_key","")) != encounter_key or String(payload.get("expedition_id","")) != expedition_id or String(payload.get("player_id","")) != player_id:
		return {"ok":false,"reason":"world_snapshot_context_mismatch"}
	for key in ["expedition","repository","character","receipt","receipt_sha256","checkpoint_fingerprint","checkpoint_round"]:
		if not payload.has(key):
			return {"ok":false,"reason":"world_snapshot_missing_" + key}
	if not payload["expedition"] is Dictionary or not payload["repository"] is Dictionary or not payload["character"] is Dictionary or not payload["receipt"] is Dictionary:
		return {"ok":false,"reason":"world_snapshot_invalid_shape"}
	if not payload["receipt_sha256"] is String or String(payload["receipt_sha256"]).length() != 64:
		return {"ok":false,"reason":"world_snapshot_invalid_receipt_hash"}
	var receipt: Dictionary = payload["receipt"]
	if String(receipt.get("encounter_key","")) != encounter_key or String(receipt.get("expedition_id","")) != expedition_id or String(receipt.get("player_id","")) != player_id or String(receipt.get("winning_team","")) != "players":
		return {"ok":false,"reason":"world_snapshot_receipt_identity_mismatch"}
	# The settlement journal's SHA covers the ORIGINAL receipt JSON bytes.
	# Never re-hash a decoded Dictionary here: Godot can normalize numeric
	# types during parsing. The world envelope hashes the full payload and
	# the expedition's immutable marker pins its originating receipt SHA.
	var expedition_data: Dictionary = payload["expedition"]
	if String(expedition_data.get("expedition_id","")) != expedition_id or not expedition_data.get("world_state") is Dictionary:
		return {"ok":false,"reason":"world_snapshot_expedition_invalid"}
	var world: Dictionary = expedition_data["world_state"]
	if String(Dictionary(world.get(MapCombatSettlementService.MARKER_KEY,{})).get(encounter_key,"")) != String(payload["receipt_sha256"]):
		return {"ok":false,"reason":"world_snapshot_missing_settlement_marker"}
	var issue := _validate_tombstones(world,encounter_key,String(payload["receipt_sha256"]),receipt)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	var repository_data: Dictionary = payload["repository"]
	if not repository_data.get("items") is Dictionary:
		return {"ok":false,"reason":"world_snapshot_repository_invalid"}
	var repository := ItemRepository.from_dict(repository_data)
	if repository.size() != Dictionary(repository_data["items"]).size():
		return {"ok":false,"reason":"world_snapshot_repository_items_rejected"}
	var restored_character := _restore_character(payload["character"],repository)
	if not bool(restored_character.get("ok",false)):
		return restored_character
	var character: CharacterState = restored_character["character"]
	if character.character_id != player_id:
		return {"ok":false,"reason":"world_snapshot_character_mismatch"}
	if not CharacterProgression._is_whole_number(payload["checkpoint_round"]) or int(payload["checkpoint_round"]) < 1:
		return {"ok":false,"reason":"world_snapshot_checkpoint_round_invalid"}
	if not payload["checkpoint_fingerprint"] is String or String(payload["checkpoint_fingerprint"]).length() != 64:
		return {"ok":false,"reason":"world_snapshot_fingerprint_invalid"}
	var expedition := ExpeditionState.from_dict(expedition_data)
	return {"ok":true,"expedition":expedition,"repository":repository,"character":character,
		"receipt_sha256":String(payload["receipt_sha256"]),"checkpoint_fingerprint":String(payload["checkpoint_fingerprint"]),
		"checkpoint_round":int(payload["checkpoint_round"]),"snapshot_sha256":String(loaded["hash"])}

## Do not stage a snapshot from an uncommitted or fabricated victory.
## This must run after HexMapTurnService.resolve_group_victory_durable()
## and AFTER CharacterState.commit_combat_resources() on the actual winner.
static func commit(session: Dictionary, encounter_key: String, expedition: ExpeditionState, map, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository, receipt_path: String = MapCombatSettlementService.DEFAULT_PATH, checkpoint_path: String = GroupCombatCheckpointService.DEFAULT_PATH, snapshot_path: String = DEFAULT_PATH) -> Dictionary:
	if expedition == null or map == null or bridge == null or player == null or repository == null:
		return {"ok":false,"reason":"world_commit_missing_dependencies"}
	if not _valid_id(encounter_key) or not _valid_id(expedition.expedition_id) or not _valid_id(player.character_id) or not _valid_path(snapshot_path) or not _valid_path(receipt_path) or not _valid_path(checkpoint_path) or snapshot_path == receipt_path or snapshot_path == checkpoint_path or receipt_path == checkpoint_path:
		return {"ok":false,"reason":"world_commit_invalid_context"}
	var journal := MapCombatSettlementService.read(receipt_path,encounter_key,expedition.expedition_id,player.character_id)
	if not bool(journal.get("ok",false)):
		return {"ok":false,"reason":String(journal.get("reason","world_commit_missing_receipt"))}
	var receipt: Dictionary = journal["receipt"]
	var receipt_hash := String(journal["sha256"])
	var markers: Dictionary = expedition.world_state.get(MapCombatSettlementService.MARKER_KEY,{})
	if String(markers.get(encounter_key,"")) != receipt_hash:
		return {"ok":false,"reason":"world_commit_settlement_not_applied"}
	var sim: GroupCombatSimulator = session.get("simulator") as GroupCombatSimulator
	if sim == null or sim.checkpoint_path != checkpoint_path or sim.checkpoint_encounter_key != encounter_key:
		return {"ok":false,"reason":"world_commit_session_mismatch"}
	var checkpoint := GroupCombatCheckpointService.read(checkpoint_path,encounter_key,sim.checkpoint_roster_fingerprint)
	if not bool(checkpoint.get("ok",false)) or not bool(checkpoint.get("terminal",false)):
		return {"ok":false,"reason":"world_commit_terminal_checkpoint_missing"}
	var disk_sim: GroupCombatSimulator = checkpoint["simulator"]
	if disk_sim.controller.winning_team() != "players" or disk_sim.state.round_number != int(receipt["round"]):
		return {"ok":false,"reason":"world_commit_terminal_outcome_mismatch"}
	var winner: CombatantState = disk_sim.state.get_combatant(player.character_id)
	if winner == null:
		return {"ok":false,"reason":"world_commit_player_not_in_battle"}
	# Do not silently persist pre-battle current HP/mana. The caller must
	# reconcile the combat result with canonical character PAR first.
	var resources: Dictionary = player.resource_snapshot(repository)
	if resources.is_empty() or winner.max_hp != int(resources["max_hp"]) or winner.max_mana != int(resources["max_mana"]) or player.current_hp != clampi(winner.visible_hp(),0,int(resources["max_hp"])) or player.current_mana != clampi(winner.mana,0,int(resources["max_mana"])):
		return {"ok":false,"reason":"world_commit_combat_resources_not_committed"}
	for raw_id in Array(receipt["npc_ids"]):
		var id := String(raw_id)
		if not bridge.instances.has(id) or bridge.instances[id] == null or bridge.instances[id].is_alive() or map.entity_positions.has(id):
			return {"ok":false,"reason":"world_commit_npc_still_active","npc_id":id}
	var expedition_data := expedition.to_dict()
	var world: Dictionary = expedition_data["world_state"]
	var completed: Dictionary = Dictionary(world.get(TOMBSTONES_KEY,{})).duplicate(true)
	var tombstone := {"receipt_sha256":receipt_hash,
		"npc_ids":Array(receipt["npc_ids"]).duplicate(true),
		"npc_positions":Dictionary(receipt["npc_positions"]).duplicate(true)}
	if completed.has(encounter_key) and JSON.stringify(completed[encounter_key]) != JSON.stringify(tombstone):
		return {"ok":false,"reason":"world_commit_tombstone_conflict"}
	completed[encounter_key] = tombstone
	world[TOMBSTONES_KEY] = completed
	expedition_data["world_state"] = world
	var data: Dictionary = {
		"version":VERSION,"encounter_key":encounter_key,
		"expedition_id":expedition.expedition_id,"player_id":player.character_id,
		"receipt":receipt.duplicate(true),"receipt_sha256":receipt_hash,
		"checkpoint_fingerprint":sim.checkpoint_roster_fingerprint,
		"checkpoint_round":disk_sim.state.round_number,
		"expedition":expedition_data,"repository":repository.to_dict(),
		"character":_character_to_dict(player)
	}
	# A previously committed snapshot must never be overwritten with a
	# different local encounter/owner. These V1 files are single-encounter.
	if FileAccess.file_exists(snapshot_path):
		var previous := _read_envelope(snapshot_path)
		if not bool(previous.get("ok",false)):
			return {"ok":false,"reason":"world_commit_existing_snapshot_invalid"}
		var prior: Dictionary = previous["payload"]
		if String(prior.get("encounter_key","")) != encounter_key or String(prior.get("expedition_id","")) != expedition.expedition_id or String(prior.get("player_id","")) != player.character_id or String(prior.get("receipt_sha256","")) != receipt_hash:
			return {"ok":false,"reason":"world_commit_existing_snapshot_conflict"}
	var written := _write_verified_payload(data,snapshot_path)
	if not bool(written.get("ok",false)):
		return written
	# In-memory world becomes authoritative only after the disk snapshot
	# can be independently read and fully reconstructed.
	expedition.world_state[TOMBSTONES_KEY] = completed
	return {"ok":true,"snapshot_path":snapshot_path,"receipt_sha256":receipt_hash,"checkpoint_round":disk_sim.state.round_number}

## Validate a complete reconstructable TEMP snapshot before atomically
## replacing the authoritative file. This prevents malformed new data from
## destroying a previously valid world snapshot.
static func _write_verified_payload(data: Dictionary, path: String) -> Dictionary:
	if not _valid_path(path):
		return {"ok":false,"reason":"invalid_world_commit_path"}
	var raw := JSON.stringify(data)
	var wrapper := JSON.stringify({"format":FORMAT,"payload_json":raw,"sha256":raw.sha256_text()})
	if wrapper.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok":false,"reason":"world_commit_too_large"}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"world_commit_temp_open_failed"}
	file.store_string(wrapper)
	file.flush()
	file.close()
	var prepared := read(temp,String(data["encounter_key"]),String(data["expedition_id"]),String(data["player_id"]))
	if not bool(prepared.get("ok",false)):
		return {"ok":false,"reason":"world_commit_temp_verification_failed","detail":String(prepared.get("reason","unknown"))}
	var renamed := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	if renamed != OK:
		return {"ok":false,"reason":"world_commit_atomic_replace_failed","error":renamed}
	return {"ok":true,"snapshot_path":path,"snapshot_sha256":raw.sha256_text()}

## Persist subsequent item claims, expiry cleanup, or normal character changes
## into the SAME atomic world snapshot after receipt acknowledgement. All
## claimed/expired loot must only disappear; no old drop can be resurrected.
static func save_progress(path: String, encounter_key: String, expedition: ExpeditionState, player: CharacterState, repository: ItemRepository) -> Dictionary:
	if expedition == null or player == null or repository == null:
		return {"ok":false,"reason":"world_progress_missing_dependencies"}
	var previous := read(path,encounter_key,expedition.expedition_id,player.character_id)
	if not bool(previous.get("ok",false)):
		return {"ok":false,"reason":"world_progress_snapshot_not_verified","detail":String(previous.get("reason","unknown"))}
	var envelope := _read_envelope(path)
	if not bool(envelope.get("ok",false)):
		return envelope
	var original: Dictionary = envelope["payload"]
	var old_expedition: Dictionary = original["expedition"]
	var previous_world: Dictionary = old_expedition["world_state"]
	var next_expedition: Dictionary = expedition.to_dict()
	var next_world: Dictionary = next_expedition["world_state"]
	if JSON.stringify(next_world.get(TOMBSTONES_KEY,{})) != JSON.stringify(previous_world.get(TOMBSTONES_KEY,{})):
		return {"ok":false,"reason":"world_progress_tombstones_changed"}
	if String(Dictionary(next_world.get(MapCombatSettlementService.MARKER_KEY,{})).get(encounter_key,"")) != String(original["receipt_sha256"]):
		return {"ok":false,"reason":"world_progress_marker_missing"}
	var old_pool: EncounterLootPool = ExpeditionState.from_dict(old_expedition).restore_loot_pool(encounter_key)
	var new_pool: EncounterLootPool = expedition.restore_loot_pool(encounter_key)
	if old_pool == null and new_pool != null:
		return {"ok":false,"reason":"world_progress_loot_resurrected"}
	if old_pool != null and new_pool != null:
		for id in new_pool.item_ids():
			if not old_pool.item_ids().has(id):
				return {"ok":false,"reason":"world_progress_new_reward_in_old_pool","item_id":id}
	var updated := original.duplicate(true)
	updated["expedition"] = next_expedition
	updated["repository"] = repository.to_dict()
	updated["character"] = _character_to_dict(player)
	return _write_verified_payload(updated,path)

## After a verified world snapshot, the receipt/checkpoint are redundant.
## If app death happens between the two deletes, rerunning is safe:
## the independently restorable snapshot is already authoritative.
static func acknowledge(snapshot_path: String, receipt_path: String, checkpoint_path: String, encounter_key: String, expedition_id: String, player_id: String) -> Dictionary:
	if not _valid_path(snapshot_path) or not _valid_path(receipt_path) or not _valid_path(checkpoint_path) or snapshot_path == receipt_path or snapshot_path == checkpoint_path or receipt_path == checkpoint_path:
		return {"ok":false,"reason":"invalid_world_ack_paths"}
	var committed := read(snapshot_path,encounter_key,expedition_id,player_id)
	if not bool(committed.get("ok",false)):
		return {"ok":false,"reason":"world_ack_snapshot_not_verified","detail":String(committed.get("reason","unknown"))}
	if FileAccess.file_exists(receipt_path):
		var journal := MapCombatSettlementService.read(receipt_path,encounter_key,expedition_id,player_id)
		if not bool(journal.get("ok",false)) or String(journal.get("sha256","")) != String(committed["receipt_sha256"]):
			return {"ok":false,"reason":"world_ack_receipt_mismatch"}
	if FileAccess.file_exists(checkpoint_path):
		var fight := GroupCombatCheckpointService.read(checkpoint_path,encounter_key,String(committed["checkpoint_fingerprint"]))
		if not bool(fight.get("ok",false)) or not bool(fight.get("terminal",false)) or int(fight.get("round",-1)) != int(committed["checkpoint_round"]):
			return {"ok":false,"reason":"world_ack_terminal_checkpoint_mismatch"}
	if FileAccess.file_exists(receipt_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(receipt_path)) != OK:
		return {"ok":false,"reason":"world_ack_receipt_remove_failed"}
	if not GroupCombatCheckpointService.clear(checkpoint_path):
		return {"ok":false,"reason":"world_ack_checkpoint_remove_failed"}
	return {"ok":true,"snapshot_survives":FileAccess.file_exists(snapshot_path)}

## World generator guard: stop the exact same NPC ID from respawning even
## after the receipt and combat checkpoint have been acknowledged/cleared.
static func is_defeated_spawn(expedition: ExpeditionState, npc_id: String) -> bool:
	if expedition == null or npc_id.is_empty():
		return false
	var cohorts: Dictionary = expedition.world_state.get(TOMBSTONES_KEY,{})
	for raw in cohorts.values():
		if raw is Dictionary and Array(raw.get("npc_ids",[])).has(npc_id):
			return true
	return false

## Reconcile a freshly generated world before enabling movement or patrol.
## Missing NPCs are acceptable (already suppressed by the generator).
## Every present NPC/position is validated before mutating any entity.
static func reconcile_map(expedition: ExpeditionState, map, bridge: MapNpcBridge) -> Dictionary:
	if expedition == null or map == null or bridge == null:
		return {"ok":false,"reason":"invalid_world_reconcile_context"}
	var cohorts: Variant = expedition.world_state.get(TOMBSTONES_KEY,{})
	if not cohorts is Dictionary:
		return {"ok":false,"reason":"invalid_world_tombstone_registry"}
	var positions: Dictionary = {}
	for raw in cohorts.values():
		if not raw is Dictionary or not raw.get("npc_ids") is Array or not raw.get("npc_positions") is Dictionary:
			return {"ok":false,"reason":"invalid_world_tombstone"}
		for raw_id in Array(raw["npc_ids"]):
			var id := String(raw_id)
			if not Dictionary(raw["npc_positions"]).has(id):
				return {"ok":false,"reason":"world_reconcile_missing_position"}
			if positions.has(id):
				return {"ok":false,"reason":"world_reconcile_duplicate_npc"}
			var coords: Variant = raw["npc_positions"][id]
			if not coords is Array or Array(coords).size() != 2:
				return {"ok":false,"reason":"world_reconcile_bad_position"}
			positions[id] = Vector2i(int(coords[0]),int(coords[1]))
	for id in positions.keys():
		if not bridge.instances.has(id):
			continue
		var npc: NpcInstance = bridge.instances[id]
		if npc == null:
			return {"ok":false,"reason":"world_reconcile_invalid_npc"}
		if npc.is_alive():
			if not map.entity_positions.has(id) or map.entity_positions[id] != positions[id]:
				return {"ok":false,"reason":"world_reconcile_npc_position_mismatch","npc_id":id}
		elif map.entity_positions.has(id):
			return {"ok":false,"reason":"world_reconcile_dead_npc_on_map","npc_id":id}
	var killed := 0
	for id in positions.keys():
		if not bridge.instances.has(id):
			continue
		var npc: NpcInstance = bridge.instances[id]
		if npc.is_alive():
			if not bridge.resolve_death(map,id):
				return {"ok":false,"reason":"world_reconcile_npc_death_failed","npc_id":id}
			killed += 1
	return {"ok":true,"deaths_applied":killed}

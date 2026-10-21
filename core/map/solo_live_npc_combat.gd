class_name SoloLiveNpcCombat
extends RefCounted

## First REAL, checkpointed Solo map encounter. Uses the canonical combat
## builder and GroupCombatSimulator, never a fixture or fake winner.
## Basic attacks are currently auto-selected by the simulator.
var owner: SoloLiveMapSession
var turns: HexMapTurnService
var battle: Dictionary
var encounter_key: String
var checkpoint_path: String
var receipt_path: String
var terminal_path: String
var target_cell: Vector2i

static func _paths(expedition_id: String, npc_id: String, attempt: int = 1) -> Dictionary:
	var key := "solo:live:" + expedition_id + ":" + npc_id
	if attempt > 1:
		key += ":attempt_" + str(attempt)
	var digest := key.sha256_text().substr(0,24)
	return {"encounter_key":key,"checkpoint":"user://solo_live_fight_"+digest+".json","receipt":"user://solo_live_receipt_"+digest+".json","terminal":"user://solo_live_world_"+digest+".json"}

## Losing to a living NPC must not mark the NPC dead. A retry uses a
## different durable encounter key, preserving every earlier defeat record.
static func _next_attempt(session: SoloLiveMapSession, npc_id: String) -> int:
	var key := "solo:live:" + session.expedition.expedition_id + ":" + npc_id
	var previous: Dictionary = session.expedition.world_state.get(SoloCombatDefeatService.LEDGER_KEY,{})
	var count := 0
	for old_key in previous.keys():
		var old := String(old_key)
		if old == key or old.begins_with(key + ":attempt_"):
			count += 1
	return count + 1

## Failed contact reconstruction must not leave a ghost player on the NPC
## tile. The persisted expedition position always remains authoritative.
static func _restore_precombat_position(session: SoloLiveMapSession) -> void:
	if session != null and session.map != null and session.character != null and session.expedition != null:
		session.map.entity_positions[session.character.character_id] = session.expedition.player_position

static func start(session: SoloLiveMapSession, cell: Vector2i) -> Dictionary:
	if session == null or session.map == null or session.npc_bridge == null or session.character == null:
		return {"ok":false,"reason":"invalid_live_combat_context"}
	if not session.expedition.is_active() or FileAccess.file_exists(session.manifest_path):
		return {"ok":false,"reason":"pending_combat_or_closed_expedition"}
	if HexGrid.distance(session.expedition.player_position,cell) != 1:
		return {"ok":false,"reason":"enemy_not_adjacent"}
	var contact := session.npc_bridge.encounter_at(session.map,cell)
	if not bool(contact.get("ok",false)):
		return {"ok":false,"reason":"no_enemy_at_cell"}
	var ids: Array = contact.get("npc_instance_ids",[])
	if ids.is_empty():
		return {"ok":false,"reason":"empty_npc_cohort"}
	var files := _paths(session.expedition.expedition_id,String(ids[0]),_next_attempt(session,String(ids[0])))
	if FileAccess.file_exists(String(files["terminal"])) or FileAccess.file_exists(String(files["receipt"])) or FileAccess.file_exists(String(files["checkpoint"])):
		return {"ok":false,"reason":"old_combat_artifact_requires_reconciliation"}
	var manifest := SoloCombatSessionManifest.begin(session.manifest_path,session.save_path,String(files["terminal"]),String(files["checkpoint"]),String(files["encounter_key"]),session.expedition.expedition_id,session.character.character_id)
	if not bool(manifest.get("ok",false)):
		return manifest
	# Start real NPC contact only after durable pre-combat registration.
	var turns_instance := HexMapTurnService.new()
	var contact_result := turns_instance.move_player(session.map,session.npc_bridge,session.character.character_id,cell,RandomNumberGenerator.new())
	if not bool(contact_result.get("ok",false)) or not contact_result.has("encounter"):
		_restore_precombat_position(session)
		return {"ok":false,"reason":"map_encounter_start_failed"}
	var catalog := NpcRepository.new()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/starting_region_npcs.json"))
	if not raw is Dictionary:
		_restore_precombat_position(session)
		return {"ok":false,"reason":"npc_catalog_unavailable"}
	catalog.load_definitions(raw)
	var fighter := CharacterCombatBuilder.build(session.character,session.repository)
	if fighter == null:
		_restore_precombat_position(session)
		return {"ok":false,"reason":"player_combat_build_failed"}
	var opened := turns_instance.begin_resumable_group_combat(contact_result["encounter"],catalog,fighter,String(files["encounter_key"]),String(files["checkpoint"]))
	if not bool(opened.get("ok",false)):
		_restore_precombat_position(session)
		return opened
	var live := SoloLiveNpcCombat.new()
	live.owner=session
	live.turns=turns_instance
	live.battle=opened
	live.encounter_key=String(files["encounter_key"])
	live.checkpoint_path=String(files["checkpoint"])
	live.receipt_path=String(files["receipt"])
	live.terminal_path=String(files["terminal"])
	live.target_cell=cell
	return {"ok":true,"combat":live}

## Restore the SAME NPC cohort and checkpoint after a process restart.
## A missing/corrupt checkpoint is never replaced by a fresh encounter.
static func resume(session: SoloLiveMapSession) -> Dictionary:
	if session == null or session.map == null:
		return {"ok":false,"reason":"invalid_resume_session"}
	var record := SoloCombatSessionManifest.read(session.manifest_path)
	if not bool(record.get("ok",false)):
		return record
	var data: Dictionary = record["data"]
	if String(data.get("expedition_path","")) != session.save_path or String(data.get("expedition_id","")) != session.expedition.expedition_id or String(data.get("player_id","")) != session.character.character_id:
		return {"ok":false,"reason":"resume_owner_mismatch"}
	var checkpoint := String(data["checkpoint_path"])
	if not FileAccess.file_exists(checkpoint) or FileAccess.file_exists(String(data["terminal_path"])):
		return {"ok":false,"reason":"resume_checkpoint_missing_or_terminal"}
	var match_cell := Vector2i(-1,-1)
	var npc_id := ""
	for id in session.npc_bridge.instances:
		var expected := _paths(session.expedition.expedition_id,String(id),_next_attempt(session,String(id)))
		if String(expected["encounter_key"]) == String(data["encounter_key"]) and String(expected["checkpoint"]) == checkpoint and String(expected["terminal"]) == String(data["terminal_path"]):
			npc_id = String(id)
			match_cell = session.map.entity_positions.get(npc_id,Vector2i(-1,-1))
			break
	if npc_id.is_empty() or HexGrid.distance(session.expedition.player_position,match_cell) != 1:
		return {"ok":false,"reason":"resume_encounter_position_invalid"}
	var turn := HexMapTurnService.new()
	var contact := turn.move_player(session.map,session.npc_bridge,session.character.character_id,match_cell,RandomNumberGenerator.new())
	if not bool(contact.get("ok",false)) or not contact.has("encounter"):
		_restore_precombat_position(session)
		return {"ok":false,"reason":"resume_contact_invalid"}
	var catalog := NpcRepository.new()
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/starting_region_npcs.json"))
	if not document is Dictionary:
		_restore_precombat_position(session)
		return {"ok":false,"reason":"resume_npc_catalog_invalid"}
	catalog.load_definitions(document)
	var fighter := CharacterCombatBuilder.build(session.character,session.repository)
	if fighter == null:
		_restore_precombat_position(session)
		return {"ok":false,"reason":"resume_player_invalid"}
	var opened := turn.begin_resumable_group_combat(contact["encounter"],catalog,fighter,String(data["encounter_key"]),checkpoint)
	if not bool(opened.get("ok",false)) or not bool(opened.get("resumed",false)):
		_restore_precombat_position(session)
		return {"ok":false,"reason":"resume_checkpoint_rejected","detail":String(opened.get("reason","unknown"))}
	var instance := SoloLiveNpcCombat.new()
	instance.owner = session
	instance.turns = turn
	instance.battle = opened
	instance.encounter_key = String(data["encounter_key"])
	instance.checkpoint_path = checkpoint
	instance.receipt_path = String(_paths(session.expedition.expedition_id,npc_id,_next_attempt(session,npc_id))["receipt"])
	instance.terminal_path = String(data["terminal_path"])
	instance.target_cell = match_cell
	return {"ok":true,"combat":instance,"round":opened["simulator"].state.round_number}

func play_round() -> Dictionary:
	var simulator: GroupCombatSimulator = battle["simulator"]
	if not simulator.controller.combat_finished():
		var step := simulator.run_round()
		if not bool(step.get("ok",false)) or not bool(step.get("checkpoint_ok",false)):
			return {"ok":false,"reason":"combat_round_checkpoint_failed","detail":String(step.get("checkpoint_reason",step.get("reason","unknown")))}
	if not simulator.controller.combat_finished():
		return {"ok":true,"state":"ongoing","round":simulator.state.round_number}
	if simulator.controller.winning_team() != "players":
		var staged := SoloCombatDefeatService.stage(owner,battle,encounter_key,checkpoint_path,terminal_path)
		if not bool(staged.get("ok",false)):
			return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_staging_failed","detail":String(staged.get("reason","unknown"))}
		var published := SoloCombatSessionManifest.recover_on_launch(owner.manifest_path)
		if not bool(published.get("ok",false)):
			return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_publish_failed","detail":String(published.get("reason","unknown"))}
		return {"ok":true,"state":"defeat","round":simulator.state.round_number,"return_cell":staged["return_cell"]}
	var committed := turns.finalize_group_victory_atomic(battle,encounter_key,owner.expedition,owner.map,owner.npc_bridge,owner.character,owner.repository,NpcPossessionLootService.new(1),{"common":100.0},receipt_path,checkpoint_path,terminal_path,int(Time.get_unix_time_from_system()),true)
	if not bool(committed.get("ok",false)):
		return {"ok":false,"reason":"world_commit_failed","detail":String(committed.get("reason","unknown"))}
	var recovered := SoloCombatSessionManifest.recover_on_launch(owner.manifest_path)
	if not bool(recovered.get("ok",false)):
		return {"ok":false,"reason":"expedition_publish_failed","detail":String(recovered.get("reason","unknown"))}
	return {"ok":true,"state":"victory","round":simulator.state.round_number,"loot_cell":target_cell}

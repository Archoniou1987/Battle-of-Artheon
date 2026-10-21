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

static func _paths(expedition_id: String, npc_id: String) -> Dictionary:
	var key := "solo:live:" + expedition_id + ":" + npc_id
	var digest := key.sha256_text().substr(0,24)
	return {"encounter_key":key,"checkpoint":"user://solo_live_fight_"+digest+".json","receipt":"user://solo_live_receipt_"+digest+".json","terminal":"user://solo_live_world_"+digest+".json"}

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
	var files := _paths(session.expedition.expedition_id,String(ids[0]))
	if FileAccess.file_exists(String(files["terminal"])) or FileAccess.file_exists(String(files["receipt"])) or FileAccess.file_exists(String(files["checkpoint"])):
		return {"ok":false,"reason":"old_combat_artifact_requires_reconciliation"}
	var manifest := SoloCombatSessionManifest.begin(session.manifest_path,session.save_path,String(files["terminal"]),String(files["checkpoint"]),String(files["encounter_key"]),session.expedition.expedition_id,session.character.character_id)
	if not bool(manifest.get("ok",false)):
		return manifest
	# Start real NPC contact only after durable pre-combat registration.
	var turns_instance := HexMapTurnService.new()
	var contact_result := turns_instance.move_player(session.map,session.npc_bridge,session.character.character_id,cell,RandomNumberGenerator.new())
	if not bool(contact_result.get("ok",false)) or not contact_result.has("encounter"):
		session.map.entity_positions[session.character.character_id] = session.expedition.player_position
		return {"ok":false,"reason":"map_encounter_start_failed"}
	var catalog := NpcRepository.new()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/starting_region_npcs.json"))
	if not raw is Dictionary:
		return {"ok":false,"reason":"npc_catalog_unavailable"}
	catalog.load_definitions(raw)
	var fighter := CharacterCombatBuilder.build(session.character,session.repository)
	if fighter == null:
		return {"ok":false,"reason":"player_combat_build_failed"}
	var opened := turns_instance.begin_resumable_group_combat(contact_result["encounter"],catalog,fighter,String(files["encounter_key"]),String(files["checkpoint"]))
	if not bool(opened.get("ok",false)):
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

func play_round() -> Dictionary:
	var simulator: GroupCombatSimulator = battle["simulator"]
	if simulator.controller.combat_finished():
		return {"ok":false,"reason":"combat_already_terminal"}
	var step := simulator.run_round()
	if not bool(step.get("ok",false)) or not bool(step.get("checkpoint_ok",false)):
		return {"ok":false,"reason":"combat_round_checkpoint_failed","detail":String(step.get("checkpoint_reason",step.get("reason","unknown")))}
	if not simulator.controller.combat_finished():
		return {"ok":true,"state":"ongoing","round":simulator.state.round_number}
	if simulator.controller.winning_team() != "players":
		return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_requires_explicit_map_outcome"}
	var committed := turns.finalize_group_victory_atomic(battle,encounter_key,owner.expedition,owner.map,owner.npc_bridge,owner.character,owner.repository,NpcPossessionLootService.new(1),{"common":100.0},receipt_path,checkpoint_path,terminal_path,int(Time.get_unix_time_from_system()),true)
	if not bool(committed.get("ok",false)):
		return {"ok":false,"reason":"world_commit_failed","detail":String(committed.get("reason","unknown"))}
	var recovered := SoloCombatSessionManifest.recover_on_launch(owner.manifest_path)
	if not bool(recovered.get("ok",false)):
		return {"ok":false,"reason":"expedition_publish_failed","detail":String(recovered.get("reason","unknown"))}
	return {"ok":true,"state":"victory","round":simulator.state.round_number,"loot_cell":target_cell}

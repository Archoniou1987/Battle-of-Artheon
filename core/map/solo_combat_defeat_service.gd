class_name SoloCombatDefeatService
extends RefCounted

## Defeat is NOT a victory settlement. Keep all NPCs, item instances,
## ground loot and victory receipts unchanged; only the character's
## retreat and a durable defeat marker become authoritative.
## The staged terminal is a FULL verified ExpeditionSaveService snapshot,
## never a MapWorldCommitService victory receipt.
const LEDGER_KEY := "solo_combat_defeats_v1"

static func inspect_terminal_type(path: String) -> Dictionary:
	if not MapWorldCommitService._valid_path(path) or not FileAccess.file_exists(path):
		return {"ok":false,"reason":"defeat_terminal_missing"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"defeat_terminal_open_failed"}
	if file.get_length() < 16 or file.get_length() > ExpeditionSaveService.MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"defeat_terminal_size_rejected"}
	var raw := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		return {"ok":false,"reason":"defeat_terminal_envelope_invalid"}
	var envelope: Dictionary = parser.data
	if not envelope.get("format") is String:
		return {"ok":false,"reason":"defeat_terminal_format_missing"}
	return {"ok":true,"format":String(envelope["format"])}

static func _starting_cell(expedition: ExpeditionState) -> Vector2i:
	var raw: Variant = expedition.world_state.get(ExpeditionState.SOLO_START_CELL_KEY,null)
	if raw is Array and Array(raw).size() == 2 and CharacterProgression._is_whole_number(raw[0]) and CharacterProgression._is_whole_number(raw[1]):
		return Vector2i(int(raw[0]),int(raw[1]))
	# Historical expeditions did not record a start cell. Never invent a
	# different teleport destination for those existing saves.
	return expedition.player_position

static func stage(session, battle: Dictionary, encounter_key: String, checkpoint_path: String, terminal_path: String, manifest: Dictionary) -> Dictionary:
	if session == null or session.expedition == null or session.character == null or session.repository == null:
		return {"ok":false,"reason":"defeat_invalid_owner"}
	if not MapWorldCommitService._valid_id(encounter_key) or not GroupCombatCheckpointService._valid_path(checkpoint_path) or not GroupCombatCheckpointService._valid_path(terminal_path):
		return {"ok":false,"reason":"defeat_invalid_paths"}
	if FileAccess.file_exists(terminal_path):
		return {"ok":false,"reason":"defeat_terminal_already_exists"}
	# The caller has already verified the pending manifest before staging.
	if String(manifest.get("encounter_key","")) != encounter_key or String(manifest.get("checkpoint_path","")) != checkpoint_path or String(manifest.get("terminal_path","")) != terminal_path or String(manifest.get("expedition_path","")) != session.save_path or String(manifest.get("expedition_id","")) != session.expedition.expedition_id or String(manifest.get("player_id","")) != session.character.character_id:
		return {"ok":false,"reason":"defeat_manifest_mismatch"}
	var simulator: GroupCombatSimulator = battle.get("simulator") as GroupCombatSimulator
	if simulator == null or not simulator.controller.combat_finished() or simulator.controller.winning_team() == "players" or simulator.state.round_number < 1:
		return {"ok":false,"reason":"defeat_not_terminal_loss"}
	var hero: CombatantState = simulator.state.get_combatant(session.character.character_id)
	if hero == null or not hero.is_death_finalized():
		return {"ok":false,"reason":"defeat_player_not_finalized"}
	if not FileAccess.file_exists(checkpoint_path):
		return {"ok":false,"reason":"defeat_checkpoint_missing"}
	var fingerprint := String(simulator.checkpoint_roster_fingerprint)
	var checked := GroupCombatCheckpointService.read(checkpoint_path,encounter_key,fingerprint)
	if not bool(checked.get("ok",false)):
		return {"ok":false,"reason":"defeat_checkpoint_invalid","detail":String(checked.get("reason","unknown"))}
	var persisted: GroupCombatSimulator = checked["simulator"]
	if not persisted.controller.combat_finished() or persisted.controller.winning_team() == "players" or persisted.state.round_number != simulator.state.round_number:
		return {"ok":false,"reason":"defeat_checkpoint_not_matching_terminal"}
	var persisted_hero: CombatantState = persisted.state.get_combatant(session.character.character_id)
	if persisted_hero == null or not persisted_hero.is_death_finalized():
		return {"ok":false,"reason":"defeat_checkpoint_hero_alive"}
	var current := ExpeditionSaveService._read_payload_envelope(session.save_path)
	if not bool(current.get("ok",false)) or String(current.get("sha256","")) != String(manifest.get("base_sha256","")):
		return {"ok":false,"reason":"defeat_base_revision_changed"}
	var saved := ExpeditionSaveService.read(session.save_path,session.expedition.expedition_id,session.character.character_id)
	if not bool(saved.get("ok",false)):
		return saved
	var expedition: ExpeditionState = saved["expedition"]
	var character: CharacterState = saved["character"]
	var repository: ItemRepository = saved["repository"]
	if not expedition.is_active():
		return {"ok":false,"reason":"defeat_expedition_closed"}
	var ledger: Dictionary = expedition.world_state.get(LEDGER_KEY,{})
	if ledger.has(encounter_key):
		return {"ok":false,"reason":"defeat_attempt_already_published"}
	var spawn := _starting_cell(expedition)
	if not session.map.in_bounds(spawn):
		return {"ok":false,"reason":"defeat_spawn_out_of_bounds"}
	if not character.reset_resources_to_full(repository):
		return {"ok":false,"reason":"defeat_revival_resources_invalid"}
	var checkpoint_hash := FileAccess.get_file_as_string(checkpoint_path).sha256_text()
	ledger = ledger.duplicate(true)
	ledger[encounter_key] = {
		"status":"defeat",
		"player_id":character.character_id,
		"base_sha256":String(manifest["base_sha256"]),
		"checkpoint_sha256":checkpoint_hash,
		"roster_fingerprint":fingerprint,
		"round":simulator.state.round_number,
		"return_cell":[spawn.x,spawn.y]
	}
	expedition.world_state[LEDGER_KEY] = ledger
	expedition.player_position = spawn
	var stored := ExpeditionSaveService.save(terminal_path,expedition,character,repository)
	if not bool(stored.get("ok",false)):
		return {"ok":false,"reason":"defeat_terminal_stage_failed","detail":String(stored.get("reason","unknown"))}
	return {"ok":true,"state":"defeat_staged","return_cell":spawn}

static func recover(manifest: Dictionary) -> Dictionary:
	var expedition_path := String(manifest.get("expedition_path",""))
	var terminal_path := String(manifest.get("terminal_path",""))
	var checkpoint_path := String(manifest.get("checkpoint_path",""))
	var encounter_key := String(manifest.get("encounter_key",""))
	var expedition_id := String(manifest.get("expedition_id",""))
	var player_id := String(manifest.get("player_id",""))
	var expected_base := String(manifest.get("base_sha256",""))
	var staged := ExpeditionSaveService.read(terminal_path,expedition_id,player_id)
	if not bool(staged.get("ok",false)):
		return {"ok":false,"reason":"defeat_terminal_invalid","detail":String(staged.get("reason","unknown"))}
	var next_exp: ExpeditionState = staged["expedition"]
	var next_player: CharacterState = staged["character"]
	var next_repo: ItemRepository = staged["repository"]
	var ledger: Dictionary = next_exp.world_state.get(LEDGER_KEY,{})
	var marker: Variant = ledger.get(encounter_key,null)
	if not marker is Dictionary:
		return {"ok":false,"reason":"defeat_terminal_marker_missing"}
	var receipt: Dictionary = marker
	if String(receipt.get("status","")) != "defeat" or String(receipt.get("player_id","")) != player_id or String(receipt.get("base_sha256","")) != expected_base or String(receipt.get("checkpoint_sha256","")).length() != 64 or String(receipt.get("roster_fingerprint","")).length() != 64 or int(receipt.get("round",-1)) < 1:
		return {"ok":false,"reason":"defeat_terminal_marker_invalid"}
	var cell: Variant = receipt.get("return_cell",null)
	if not cell is Array or Array(cell).size() != 2 or not CharacterProgression._is_whole_number(cell[0]) or not CharacterProgression._is_whole_number(cell[1]) or next_exp.player_position != Vector2i(int(cell[0]),int(cell[1])):
		return {"ok":false,"reason":"defeat_terminal_return_cell_invalid"}
	if not next_exp.is_active() or next_player.current_hp <= 0:
		return {"ok":false,"reason":"defeat_terminal_revival_invalid"}
	var current := ExpeditionSaveService.read(expedition_path,expedition_id,player_id)
	if not bool(current.get("ok",false)):
		return current
	var current_exp: ExpeditionState = current["expedition"]
	var current_ledger: Dictionary = current_exp.world_state.get(LEDGER_KEY,{})
	if current_ledger.has(encounter_key):
		if JSON.stringify(current_ledger[encounter_key]) != JSON.stringify(receipt):
			return {"ok":false,"reason":"defeat_receipt_conflict"}
		return {"ok":true,"already_published":true,"recovered":false}
	var revision := ExpeditionSaveService._read_payload_envelope(expedition_path)
	if not bool(revision.get("ok",false)) or String(revision.get("sha256","")) != expected_base:
		return {"ok":false,"reason":"defeat_base_revision_changed"}
	if not FileAccess.file_exists(checkpoint_path) or FileAccess.get_file_as_string(checkpoint_path).sha256_text() != String(receipt["checkpoint_sha256"]):
		return {"ok":false,"reason":"defeat_checkpoint_integrity_changed"}
	var verified := GroupCombatCheckpointService.read(checkpoint_path,encounter_key,String(receipt["roster_fingerprint"]))
	if not bool(verified.get("ok",false)):
		return {"ok":false,"reason":"defeat_checkpoint_invalid","detail":String(verified.get("reason","unknown"))}
	var simulator: GroupCombatSimulator = verified["simulator"]
	var hero: CombatantState = simulator.state.get_combatant(player_id)
	if not simulator.controller.combat_finished() or simulator.controller.winning_team()=="players" or hero==null or not hero.is_death_finalized() or simulator.state.round_number != int(receipt["round"]):
		return {"ok":false,"reason":"defeat_checkpoint_not_terminal_loss"}
	# Prove that staging did not forge any NPC defeats, loot, equipment or
	# unrelated world changes. The only allowed deltas are the defeat
	# receipt, return position and the explicitly provisional full heal.
	if JSON.stringify(current["repository"].to_dict()) != JSON.stringify(next_repo.to_dict()):
		return {"ok":false,"reason":"defeat_repository_changed"}
	var before_character := MapWorldCommitService._character_to_dict(current["character"])
	var after_character := MapWorldCommitService._character_to_dict(next_player)
	before_character.erase("resources")
	after_character.erase("resources")
	if JSON.stringify(before_character) != JSON.stringify(after_character):
		return {"ok":false,"reason":"defeat_character_changed"}
	var before_exp := current_exp.to_dict()
	var after_exp := next_exp.to_dict()
	var before_world: Dictionary = before_exp["world_state"]
	var after_world: Dictionary = after_exp["world_state"]
	var trimmed_ledger: Dictionary = after_world.get(LEDGER_KEY,{}).duplicate(true)
	trimmed_ledger.erase(encounter_key)
	if trimmed_ledger.is_empty() and not before_world.has(LEDGER_KEY):
		after_world.erase(LEDGER_KEY)
	else:
		after_world[LEDGER_KEY] = trimmed_ledger
	before_exp.erase("player_position")
	after_exp.erase("player_position")
	if JSON.stringify(before_exp) != JSON.stringify(after_exp):
		return {"ok":false,"reason":"defeat_world_unrelated_changes"}
	if next_exp.player_position != _starting_cell(current_exp):
		return {"ok":false,"reason":"defeat_wrong_start_cell"}
	var saved := ExpeditionSaveService.save(expedition_path,next_exp,next_player,next_repo)
	if not bool(saved.get("ok",false)):
		return {"ok":false,"reason":"defeat_publish_failed","detail":String(saved.get("reason","unknown"))}
	return {"ok":true,"already_published":false,"recovered":true}

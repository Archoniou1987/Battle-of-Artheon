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
	# A new expedition may reuse the stable player/roster IDs, but previous
	# receipt/checkpoint files are immutable. Skip their occupied attempts.
	var attempt := count + 1
	while attempt <= 10000:
		var files := _paths(session.expedition.expedition_id,npc_id,attempt)
		if not FileAccess.file_exists(String(files["checkpoint"])) and not FileAccess.file_exists(String(files["receipt"])) and not FileAccess.file_exists(String(files["terminal"])):
			return attempt
		attempt += 1
	return -1

## Solo must never silently equip development fixture ABI. New NPC
## encounters use only production definitions and the actually equipped
## player/NPC ABI identities. Restored checkpoints own their own scheduler
## snapshot, including cooldowns; never replace it after a saved round.
static func _configure_live_ability_scheduler(opened: Dictionary) -> Dictionary:
	var simulator: GroupCombatSimulator = opened.get("simulator") as GroupCombatSimulator
	if simulator == null:
		return {"ok":false,"reason":"live_ability_simulator_missing"}
	if bool(opened.get("resumed",false)):
		return {"ok":true,"resumed":true}
	var definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	if definitions.is_empty():
		return {"ok":false,"reason":"live_ability_catalog_missing"}
	var loadouts: Dictionary = {}
	for raw_id in simulator.state.combatants.keys():
		var actor: CombatantState = simulator.state.get_combatant(String(raw_id))
		if actor == null:
			return {"ok":false,"reason":"live_ability_actor_missing"}
		var equipped: Array[String] = []
		for raw_ability in CombatModifierService.abilities(actor):
			var ability_id := String(raw_ability)
			if ability_id.is_empty() or equipped.has(ability_id):
				continue
			# Unknown equipped ABI are visible as unavailable in UI, but
			# cannot resolve as invented test-only spells.
			if AbilityCatalog.definition(definitions,ability_id).is_empty():
				continue
			equipped.append(ability_id)
		loadouts[actor.combatant_id] = equipped
	simulator.attack_pipeline.ability_scheduler = AbilityScheduler.new(definitions,loadouts)
	return {"ok":true,"resumed":false}

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
	var attempt := _next_attempt(session,String(ids[0]))
	if attempt < 1:
		return {"ok":false,"reason":"combat_attempt_archive_exhausted"}
	var files := _paths(session.expedition.expedition_id,String(ids[0]),attempt)
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
	var scheduler := _configure_live_ability_scheduler(opened)
	if not bool(scheduler.get("ok",false)):
		_restore_precombat_position(session)
		return scheduler
	var live := SoloLiveNpcCombat.new()
	var active_simulator: GroupCombatSimulator = opened["simulator"]
	active_simulator.solo_elixir_owner = session.character
	active_simulator.solo_elixir_repository = session.repository
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
	var receipt := ""
	# Resume must use the ORIGINAL manifest identity, never _next_attempt:
	# the current fight already owns a checkpoint and is not a new entry.
	for id in session.npc_bridge.instances:
		var candidate := String(id)
		var base_key := "solo:live:" + session.expedition.expedition_id + ":" + candidate
		var manifest_key := String(data["encounter_key"])
		var attempt := 0
		if manifest_key == base_key:
			attempt = 1
		elif manifest_key.begins_with(base_key + ":attempt_"):
			var suffix := manifest_key.substr((base_key + ":attempt_").length())
			if suffix.is_valid_int() and int(suffix) > 1:
				attempt = int(suffix)
		if attempt < 1 or attempt > 10000:
			continue
		var expected := _paths(session.expedition.expedition_id,candidate,attempt)
		if String(expected["encounter_key"]) == manifest_key and String(expected["checkpoint"]) == checkpoint and String(expected["terminal"]) == String(data["terminal_path"]):
			npc_id = candidate
			receipt = String(expected["receipt"])
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
	# The checkpoint must retain its original ABI definitions/loadout and
	# ability counters; restoring the production catalog here would erase it.
	var validated_scheduler := _configure_live_ability_scheduler(opened)
	if not bool(validated_scheduler.get("ok",false)):
		_restore_precombat_position(session)
		return validated_scheduler
	var checkpoint_sim: GroupCombatSimulator = opened["simulator"]
	# Rehydrate charges from the original, manifest-pinned expedition's
	# repository and the canonical checkpoint event journal. No event replay.
	var restored_charges := SoloCombatElixirJournal.apply_to_baseline(checkpoint_sim.state,session.character,session.repository)
	if not bool(restored_charges.get("ok",false)):
		_restore_precombat_position(session)
		return {"ok":false,"reason":"resume_elixir_journal_invalid","detail":String(restored_charges.get("reason","unknown"))}
	session.repository = restored_charges["repository"]
	checkpoint_sim.solo_elixir_owner = session.character
	checkpoint_sim.solo_elixir_repository = session.repository
	var instance := SoloLiveNpcCombat.new()
	instance.owner = session
	instance.turns = turn
	instance.battle = opened
	instance.encounter_key = String(data["encounter_key"])
	instance.checkpoint_path = checkpoint
	instance.receipt_path = receipt
	instance.terminal_path = String(data["terminal_path"])
	instance.target_cell = match_cell
	return {"ok":true,"combat":instance,"round":opened["simulator"].state.round_number}

## Expose only disclosed active effects. The same rule is used by the
## Arena view: unrevealed instant ABI effects must remain hidden until
## the end-of-round disclosure boundary.
static func _disclosed_effects(actor: CombatantState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if actor == null:
		return result
	for raw in actor.active_effects:
		if not raw is Dictionary:
			continue
		var entry: Dictionary = raw
		if int(entry.get("remaining_rounds",0)) <= 0 or not bool(entry.get("revealed",true)):
			continue
		var definition: Dictionary = entry.get("definition",{})
		var kind := EffectPolarity.of(definition)
		if kind.is_empty():
			continue
		result.append({
			"id":String(entry.get("effect_id","")),
			"name":String(definition.get("name",entry.get("effect_id",""))),
			"polarity":kind,
			"stacks":maxi(1,int(entry.get("stacks",1))-maxi(0,int(entry.get("undisclosed_stacks",0)))),
			"remaining_rounds":int(entry.get("visible_remaining_rounds",entry.get("remaining_rounds",0)))
		})
	return result

## Read-only projection of the exact persisted GroupCombatSimulator.
## No secondary Arena combat session or recreated NPC stats.
func combat_view() -> Dictionary:
	if battle.is_empty():
		return {"ok":false,"reason":"combat_not_started"}
	var simulator: GroupCombatSimulator = battle.get("simulator") as GroupCombatSimulator
	if simulator == null or owner == null or owner.character == null:
		return {"ok":false,"reason":"combat_view_missing_owner"}
	var player_id := owner.character.character_id
	var hero: CombatantState = simulator.state.get_combatant(player_id)
	if hero == null:
		return {"ok":false,"reason":"combat_view_player_missing"}
	var controls := simulator.player_controls(player_id)
	var available_options: Dictionary = {}
	for raw_option in Array(controls.get("abilities",[])):
		if raw_option is Dictionary:
			var option: Dictionary = raw_option
			available_options[String(option.get("id",""))] = option
	var elixir_loadout := SoloCombatElixirLoadout.inspect(owner.character,owner.repository)
	var worn: Array[Dictionary] = []
	for slot_id in ["head","chest","hands","waist","legs","main_hand","off_hand","ring1","ring2","feet"]:
		var raw_equipped: Variant = owner.character.equipment.get_equipped_instance_id(slot_id)
		var instance_id := "" if raw_equipped == null else String(raw_equipped)
		var item: Dictionary = owner.repository.get_item(instance_id) if not instance_id.is_empty() else {}
		worn.append({
			"slot":slot_id,"instance_id":instance_id,
			"name":String(item.get("name",item.get("display_name",item.get("template_id",instance_id)))) if not item.is_empty() else "",
			"active":not instance_id.is_empty() and owner.character.is_equipment_active(instance_id,owner.repository),
			"rarity":String(item.get("rarity","")) if not item.is_empty() else ""
		})
	var equipment_slots := EquipmentAbilityLoadout.build(owner.character,owner.repository)
	var five_slots: Array[Dictionary] = []
	for category in ["weapon","chest","head"]:
		for raw_ability in Array(equipment_slots.get(category,[])):
			var equipped_id := "" if raw_ability == null else String(raw_ability)
			var slot: Dictionary = {
				"id":equipped_id,"category":category,
				"name":"Пусто" if equipped_id.is_empty() else equipped_id,
				"available":false,"mana_cost":0,"cooldown_until":0
			}
			if available_options.has(equipped_id):
				slot.merge(Dictionary(available_options[equipped_id]),true)
			five_slots.append(slot)
	var enemy_views: Array[Dictionary] = []
	for raw_id in Array(battle.get("npc_instance_ids",[])):
		var npc: CombatantState = simulator.state.get_combatant(String(raw_id))
		if npc == null:
			continue
		enemy_views.append({"id":npc.combatant_id,"name":npc.display_name,"hp":npc.visible_hp(),"max_hp":npc.max_hp,"mana":npc.mana,"max_mana":npc.max_mana,"dead":npc.is_death_finalized(),"effects":_disclosed_effects(npc)})
	var ability_definitions: Dictionary = simulator.attack_pipeline.ability_scheduler.definitions
	var log_lines: Array[String] = ArenaCombatLog.lines_for_round(simulator.state.event_log,simulator.state.round_number,player_id,ability_definitions)
	# The journal may contain several EFFECT components for one drink;
	# show one resolved item-use line, never recompute its actual effects.
	var displayed_drinks: Dictionary = {}
	for event in simulator.state.event_log:
		if event.kind != CombatEvent.Kind.EFFECT or int(event.payload.get("round",-1)) != simulator.state.round_number or String(event.payload.get("source_type","")) != "elixir" or event.source_id != player_id:
			continue
		var consumed_id := String(event.payload.get("source_instance_id",""))
		if displayed_drinks.has(consumed_id):
			continue
		displayed_drinks[consumed_id] = true
		var item := owner.repository.get_item(consumed_id)
		log_lines.append("Эликсир: " + String(item.get("name",consumed_id)) + " — использован")
	# The canonical event log is checkpointed with the simulator.
	# Reconstruct ALL completed rounds on every snapshot, including resume
	# after days offline. Never maintain a separate, fragile UI-side journal.
	var battle_lines: Array[String] = []
	for completed_round in range(simulator.state.round_number,0,-1):
		var round_lines := ArenaCombatLog.lines_for_round(simulator.state.event_log,completed_round,player_id,ability_definitions)
		var used_potions: Dictionary = {}
		for event in simulator.state.event_log:
			if event.kind != CombatEvent.Kind.EFFECT or int(event.payload.get("round",-1)) != completed_round or String(event.payload.get("source_type","")) != "elixir" or event.source_id != player_id:
				continue
			var potion_id := String(event.payload.get("source_instance_id",""))
			if used_potions.has(potion_id):
				continue
			used_potions[potion_id] = true
			var potion_item: Dictionary = owner.repository.get_item(potion_id)
			round_lines.append("Эликсир: "+String(potion_item.get("name",potion_id))+" — использован")
		if not round_lines.is_empty():
			battle_lines.append("── Раунд %d ──" % completed_round)
			battle_lines.append_array(round_lines)
	return {
		"ok":true,
		"battle_log":battle_lines,
		"round":simulator.state.round_number,
		"finished":simulator.controller.combat_finished(),
		"winner":simulator.controller.winning_team(),
		"player":{"id":player_id,"name":hero.display_name,"hp":hero.visible_hp(),"max_hp":hero.max_hp,"mana":hero.mana,"max_mana":hero.max_mana,"dead":hero.is_death_finalized(),"effects":_disclosed_effects(hero)},
		"enemies":enemy_views,
		"equipment_slots":worn,
		"ability_slots":five_slots,
		"elixir_loadout":elixir_loadout,
		"controls":controls,
		"last_round_log":log_lines
	}

func play_round(player_orders: Dictionary = {}) -> Dictionary:
	var simulator: GroupCombatSimulator = battle["simulator"]
	if not simulator.controller.combat_finished():
		var step := simulator.run_round(player_orders)
		if not bool(step.get("ok",false)):
			return {"ok":false,"reason":String(step.get("reason","combat_round_rejected")),"expected":step.get("expected",-1)}
		if not bool(step.get("checkpoint_ok",false)):
			return {"ok":false,"reason":"combat_round_checkpoint_failed","detail":String(step.get("checkpoint_reason","unknown"))}
	if not simulator.controller.combat_finished():
		return {"ok":true,"state":"ongoing","round":simulator.state.round_number}
	if simulator.controller.winning_team() != "players":
		var manifest_record := SoloCombatSessionManifest.read(owner.manifest_path)
		if not bool(manifest_record.get("ok",false)):
			return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_manifest_invalid","detail":String(manifest_record.get("reason","unknown"))}
		var staged := SoloCombatDefeatService.stage(owner,battle,encounter_key,checkpoint_path,terminal_path,manifest_record["data"])
		if not bool(staged.get("ok",false)):
			return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_staging_failed","detail":String(staged.get("reason","unknown"))}
		var published := SoloCombatSessionManifest.recover_on_launch(owner.manifest_path)
		if not bool(published.get("ok",false)):
			return {"ok":false,"state":"defeat_pending_resolution","reason":"defeat_publish_failed","detail":String(published.get("reason","unknown"))}
		return {"ok":true,"state":"defeat","round":simulator.state.round_number,"return_cell":staged["return_cell"]}
	# Audit the live, charge-mutated repository against the pinned base
	# expedition and the resolved checkpoint BEFORE loot is generated.
	var baseline := ExpeditionSaveService.read(owner.save_path,owner.expedition.expedition_id,owner.character.character_id)
	if not bool(baseline.get("ok",false)):
		return {"ok":false,"reason":"victory_elixir_baseline_missing"}
	var elixir_verified := SoloCombatElixirJournal.apply_to_baseline(simulator.state,baseline["character"],baseline["repository"])
	if not bool(elixir_verified.get("ok",false)) or not SoloCombatElixirJournal.same_repository(elixir_verified["repository"],owner.repository):
		return {"ok":false,"reason":"victory_elixir_journal_mismatch","detail":String(elixir_verified.get("reason","changed"))}
	var committed := turns.finalize_group_victory_atomic(battle,encounter_key,owner.expedition,owner.map,owner.npc_bridge,owner.character,owner.repository,NpcPossessionLootService.new(1),{"common":100.0},receipt_path,checkpoint_path,terminal_path,int(Time.get_unix_time_from_system()),true)
	if not bool(committed.get("ok",false)):
		return {"ok":false,"reason":"world_commit_failed","detail":String(committed.get("reason","unknown"))}
	var recovered := SoloCombatSessionManifest.recover_on_launch(owner.manifest_path)
	if not bool(recovered.get("ok",false)):
		return {"ok":false,"reason":"expedition_publish_failed","detail":String(recovered.get("reason","unknown"))}
	return {"ok":true,"state":"victory","round":simulator.state.round_number,"loot_cell":target_cell}

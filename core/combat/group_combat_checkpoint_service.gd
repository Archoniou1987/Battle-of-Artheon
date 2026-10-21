class_name GroupCombatCheckpointService
extends RefCounted

## One versioned, encounter-bound checkpoint for world/group combat.
## It is deliberately NOT the Arena training save or CharacterState schema.
## Only fully resolved round boundaries are serializable.
const FORMAT := "BOA_GROUP_COMBAT_CHECKPOINT_V1"
const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://group_combat_checkpoint_v1.json"
const MAX_BYTES := 5 * 1024 * 1024
const MAX_EVENTS := 10000
const MAX_COMBATANTS := 32
const MAX_ROUNDS := 10000

## Fingerprint ONLY the initial canonical roster/gear contract, not mutable
## round resources, EFF, cooldowns or current HP. Compare this to a fresh
## encounter build on resume so an obsolete loadout cannot be silently reused.
static func initial_roster_fingerprint(state: CombatState) -> String:
	if state == null or state.combatants.is_empty():
		return ""
	var roster: Array[Dictionary] = []
	var ids: Array[String] = []
	for raw_id in state.combatants.keys():
		ids.append(String(raw_id))
	ids.sort()
	for id in ids:
		var c := state.get_combatant(id)
		if c == null:
			return ""
		roster.append({
			"id":id, "level":c.level, "max_hp":c.max_hp,
			"max_mana":c.max_mana, "stats":c.stats.duplicate(true),
			"combat_stats":c.combat_stats.duplicate(true),
			"armour":c.armour.duplicate(true),
			"magic_resists":c.magic_resists.duplicate(true),
			"effect_immunities":c.effect_immunities.duplicate(),
			"combat_loadout":c.combat_loadout.duplicate(true)
		})
	return JSON.stringify(roster).sha256_text()

static func _valid_identity(encounter_key: String, roster_fingerprint: String) -> bool:
	return not encounter_key.strip_edges().is_empty() and encounter_key.length() <= 160 and not roster_fingerprint.is_empty() and roster_fingerprint.length() == 64

static func _valid_path(path: String) -> bool:
	# Never read/write arbitrary resources, external storage or path traversals.
	return path.begins_with("user://") and path.length() < 220 and not path.contains("..") and not path.contains("\\") and path != "user://"

static func capture(simulator, encounter_key: String, roster_fingerprint: String) -> Dictionary:
	if simulator == null or not _valid_identity(encounter_key, roster_fingerprint):
		return {"ok":false,"reason":"invalid_checkpoint_identity"}
	var state: CombatState = simulator.state
	var group: GroupCombatState = simulator.group
	var orchestrator: RoundOrchestrator = simulator.orchestrator
	if state == null or group == null or orchestrator == null or simulator.engine == null or simulator.attack_pipeline == null:
		return {"ok":false,"reason":"missing_combat_contract"}
	if state.round_number < 1 or state.round_number > MAX_ROUNDS or state.combatants.is_empty() or state.combatants.size() > MAX_COMBATANTS:
		return {"ok":false,"reason":"invalid_checkpoint_round_or_roster"}
	if bool(simulator.round_in_progress) or int(simulator.last_completed_round) != state.round_number or not state.pending_events.is_empty() or not orchestrator.deferred_events.is_empty() or not orchestrator.movement_requests.is_empty() or not simulator.controller.engagement.pending_requests.is_empty():
		return {"ok":false,"reason":"round_not_fully_resolved"}
	if orchestrator.zone_state != null:
		return {"ok":false,"reason":"spatial_checkpoint_not_supported_v1"}
	if state.event_log.size() > MAX_EVENTS:
		return {"ok":false,"reason":"checkpoint_event_limit"}
	var rows: Array[Dictionary] = []
	for raw in state.combatants.values():
		var c: CombatantState = raw
		rows.append(_fighter_to_dict(c))
	var events: Array[Dictionary] = []
	for event in state.event_log:
		events.append({
			"id":event.event_id,"kind":int(event.kind),"source_id":event.source_id,
			"target_id":event.target_id,"parent_event_id":event.parent_event_id,
			"payload":event.payload.duplicate(true),"result":event.result.duplicate(true)
		})
	var ability: AbilityScheduler = simulator.attack_pipeline.ability_scheduler
	var payload: Dictionary = {
		"schema_version":SCHEMA_VERSION, "encounter_key":encounter_key,
		"roster_fingerprint":roster_fingerprint,
		"state":{
			"round_number":state.round_number,
			"next_event_id":state.next_event_id,
			"round_damage_by_target":state.round_damage_by_target.duplicate(true),
			"combatants":rows, "events":events
		},
		"group":{
			"teams":group.teams.duplicate(true),
			"active_opponents":group.active_opponent_by_combatant.duplicate(true),
			"engagement_lock_until_round":simulator.controller.engagement.lock_until_round.duplicate(true)
		},
		"engine":{
			"rng_state":str(simulator.engine.combat_rng.state),
			"next_effect_stack_id":simulator.engine._next_effect_stack_id,
			"canonical_effects_sha256":JSON.stringify(simulator.engine.canonical_effects).sha256_text(),
			"physical_balance":simulator.engine.physical_balance.duplicate(true)
		},
		"orchestrator":{
			"persistent_actions":orchestrator.persistent_actions.duplicate(true)
		},
		"ability":{
			"definitions":ability.definitions.duplicate(true),
			"loadouts":ability.loadouts.duplicate(true),
			"cooldowns":ability.cooldowns_by_combatant.duplicate(true),
			"cast_rounds":ability.cast_round_by_combatant.duplicate(true)
		},
		"max_rounds":simulator.max_rounds,
		"terminal":simulator.controller.combat_finished()
	}
	var error := _validate_payload(payload, encounter_key, roster_fingerprint)
	if not error.is_empty():
		return {"ok":false,"reason":error}
	return {"ok":true,"payload":payload}

static func save(simulator, path: String, encounter_key: String, roster_fingerprint: String) -> Dictionary:
	if not _valid_path(path):
		return {"ok":false,"reason":"invalid_checkpoint_path"}
	var snapshot := capture(simulator, encounter_key, roster_fingerprint)
	if not bool(snapshot.get("ok",false)):
		return snapshot
	var raw := JSON.stringify(snapshot["payload"])
	var wrapper := JSON.stringify({"format":FORMAT,"payload_json":raw,"sha256":raw.sha256_text()})
	if wrapper.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok":false,"reason":"checkpoint_too_large"}
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok":false,"reason":"checkpoint_temp_open_failed"}
	file.store_string(wrapper)
	file.flush()
	file.close()
	# Atomic rename on supported filesystems. A failed replacement leaves
	# the previous committed checkpoint intact; a stale .tmp is ignored.
	var status := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(path))
	if status != OK:
		return {"ok":false,"reason":"checkpoint_replace_failed","error":status}
	return {"ok":true,"round":simulator.state.round_number,"terminal":simulator.controller.combat_finished()}

static func read(path: String, encounter_key: String, roster_fingerprint: String) -> Dictionary:
	if not _valid_path(path) or not _valid_identity(encounter_key, roster_fingerprint):
		return {"ok":false,"reason":"invalid_checkpoint_request"}
	if not FileAccess.file_exists(path):
		return {"ok":false,"reason":"checkpoint_not_found"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok":false,"reason":"checkpoint_read_failed"}
	if file.get_length() < 10 or file.get_length() > MAX_BYTES:
		file.close()
		return {"ok":false,"reason":"checkpoint_invalid_size"}
	var serialized := file.get_as_text()
	file.close()
	var outer: Variant = JSON.parse_string(serialized)
	if not outer is Dictionary or String(outer.get("format","")) != FORMAT:
		return {"ok":false,"reason":"checkpoint_invalid_envelope"}
	var raw: Variant = outer.get("payload_json",null)
	if not raw is String or raw.is_empty() or raw.sha256_text() != String(outer.get("sha256","")):
		return {"ok":false,"reason":"checkpoint_integrity_failed"}
	var decoded: Variant = JSON.parse_string(raw)
	if not decoded is Dictionary:
		return {"ok":false,"reason":"checkpoint_invalid_payload"}
	var error := _validate_payload(decoded, encounter_key, roster_fingerprint)
	if not error.is_empty():
		return {"ok":false,"reason":error}
	# The restore factory returns a dynamically loaded script instance.
	# Godot cannot infer a concrete type via := across that boundary.
	var restored: Variant = _restore_simulator(decoded)
	if restored == null:
		return {"ok":false,"reason":"checkpoint_restore_failed"}
	if restored.controller.combat_finished() != bool(decoded["terminal"]):
		return {"ok":false,"reason":"checkpoint_terminal_state_mismatch"}
	return {"ok":true,"simulator":restored,"round":restored.state.round_number,"terminal":restored.controller.combat_finished()}

static func clear(path: String = DEFAULT_PATH) -> bool:
	if not _valid_path(path):
		return false
	var temp_path := path + ".tmp"
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

static func _fighter_to_dict(c: CombatantState) -> Dictionary:
	return {
		"id":c.combatant_id,"name":c.display_name,"level":c.level,
		"max_hp":c.max_hp,"hp":c.hp,"death_finalized":c.death_finalized,
		"one_shot_kill":c.one_shot_kill,"max_mana":c.max_mana,"mana":c.mana,
		"action_points":c.action_points,"max_action_points":c.max_action_points,
		"tempo":c.tempo,"base_tempo":c.base_tempo,"max_tempo":c.max_tempo,
		"tempo_regen":c.tempo_regen,"tempo_stun_round":c.tempo_stun_round,
		"tempo_immunity_until_round":c.tempo_immunity_until_round,
		"stats":c.stats.duplicate(true),"combat_stats":c.combat_stats.duplicate(true),
		"armour":c.armour.duplicate(true),"magic_resists":c.magic_resists.duplicate(true),
		"effect_immunities":c.effect_immunities.duplicate(),
		"active_effects":c.active_effects.duplicate(true),
		"weapon_skills":c.weapon_skills.duplicate(true),"weapon_xp":c.weapon_xp.duplicate(true),
		"combat_loadout":c.combat_loadout.duplicate(true),
		"combat_loadout_locked":c.combat_loadout_locked
	}

static func _fighter_from_dict(d: Dictionary) -> CombatantState:
	var c := CombatantState.new(String(d["id"]),String(d["name"]),int(d["level"]),int(d["max_hp"]),int(d["max_mana"]))
	c.hp = int(d["hp"])
	c.death_finalized = bool(d["death_finalized"])
	c.one_shot_kill = bool(d["one_shot_kill"])
	c.mana = int(d["mana"])
	c.action_points = int(d["action_points"])
	c.max_action_points = int(d["max_action_points"])
	c.tempo = float(d["tempo"])
	c.base_tempo = float(d["base_tempo"])
	c.max_tempo = float(d["max_tempo"])
	c.tempo_regen = float(d["tempo_regen"])
	c.tempo_stun_round = int(d["tempo_stun_round"])
	c.tempo_immunity_until_round = int(d["tempo_immunity_until_round"])
	c.stats = Dictionary(d["stats"]).duplicate(true)
	c.combat_stats = Dictionary(d["combat_stats"]).duplicate(true)
	c.armour = Dictionary(d["armour"]).duplicate(true)
	c.magic_resists = Dictionary(d["magic_resists"]).duplicate(true)
	for raw_id in Array(d["effect_immunities"]):
		c.effect_immunities.append(String(raw_id))
	for raw_effect in Array(d["active_effects"]):
		c.active_effects.append(Dictionary(raw_effect).duplicate(true))
	c.weapon_skills = Dictionary(d["weapon_skills"]).duplicate(true)
	c.weapon_xp = Dictionary(d["weapon_xp"]).duplicate(true)
	c.combat_loadout = Dictionary(d["combat_loadout"]).duplicate(true)
	c.combat_loadout_locked = bool(d["combat_loadout_locked"])
	return c

static func _restore_simulator(payload: Dictionary):
	var saved_state: Dictionary = payload["state"]
	var saved_group: Dictionary = payload["group"]
	var saved_engine: Dictionary = payload["engine"]
	var saved_ability: Dictionary = payload["ability"]
	var state := CombatState.new()
	for raw in Array(saved_state["combatants"]):
		state.add_combatant(_fighter_from_dict(Dictionary(raw)))
	state.round_number = int(saved_state["round_number"])
	state.next_event_id = int(saved_state["next_event_id"])
	state.round_damage_by_target = Dictionary(saved_state["round_damage_by_target"]).duplicate(true)
	for raw in Array(saved_state["events"]):
		var entry: Dictionary = raw
		var event := CombatEvent.new(int(entry["id"]),int(entry["kind"]),
			String(entry["source_id"]),String(entry["target_id"]),
			Dictionary(entry["payload"]),int(entry["parent_event_id"]))
		event.result = Dictionary(entry["result"]).duplicate(true)
		state.event_log.append(event)
	var group := GroupCombatState.new(state)
	for raw_team in Dictionary(saved_group["teams"]).keys():
		var team_id := String(raw_team)
		# Preserve defeated teams with zero active members; they remain
		# meaningful to the terminal outcome and the read-only group view.
		var members: Array = saved_group["teams"][raw_team]
		if members.is_empty():
			group.teams[team_id] = []
		for raw_id in members:
			if not group.add_member(team_id,String(raw_id)):
				return null
	# Runtime load avoids a compile-time type cycle: GroupCombatSimulator uses
	# this checkpoint codec after each committed round.
	var simulator_script = load("res://core/combat/group_combat_simulator.gd")
	if simulator_script == null:
		return null
	var simulator = simulator_script.new(state,group,Dictionary(saved_engine["physical_balance"]))
	simulator.engine.combat_rng.state = int(String(saved_engine["rng_state"]))
	simulator.engine._next_effect_stack_id = int(saved_engine["next_effect_stack_id"])
	# CombatAttackPipeline.rng and CombatEngine.combat_rng are the SAME object.
	simulator.attack_pipeline.rng = simulator.engine.combat_rng
	var scheduler := AbilityScheduler.new(
		Dictionary(saved_ability["definitions"]).duplicate(true),
		Dictionary(saved_ability["loadouts"]).duplicate(true))
	scheduler.cooldowns_by_combatant = Dictionary(saved_ability["cooldowns"]).duplicate(true)
	scheduler.cast_round_by_combatant = Dictionary(saved_ability["cast_rounds"]).duplicate(true)
	simulator.attack_pipeline.ability_scheduler = scheduler
	group.active_opponent_by_combatant = Dictionary(saved_group["active_opponents"]).duplicate(true)
	simulator.controller.engagement.lock_until_round = Dictionary(saved_group["engagement_lock_until_round"]).duplicate(true)
	var persistent: Array[Dictionary] = []
	for raw_action in Array(Dictionary(payload["orchestrator"]).get("persistent_actions",[])):
		persistent.append(Dictionary(raw_action).duplicate(true))
	simulator.orchestrator.persistent_actions = persistent
	simulator.max_rounds = int(payload["max_rounds"])
	simulator.last_completed_round = state.round_number
	return simulator

static func _whole(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= float(minimum) and float(value) <= float(maximum)

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _validate_payload(p: Dictionary, expected_key: String, expected_fingerprint: String) -> String:
	if not _whole(p.get("schema_version",null),SCHEMA_VERSION,SCHEMA_VERSION):
		return "checkpoint_schema_mismatch"
	if String(p.get("encounter_key","")) != expected_key or String(p.get("roster_fingerprint","")) != expected_fingerprint:
		return "checkpoint_context_mismatch"
	for key in ["state","group","engine","orchestrator","ability"]:
		if not p.get(key) is Dictionary:
			return "checkpoint_missing_" + key
	var s: Dictionary = p["state"]
	var g: Dictionary = p["group"]
	var e: Dictionary = p["engine"]
	var o: Dictionary = p["orchestrator"]
	var a: Dictionary = p["ability"]
	if not _whole(s.get("round_number",null),1,MAX_ROUNDS) or not _whole(s.get("next_event_id",null),1,2147483647):
		return "checkpoint_invalid_round_counter"
	if not _whole(p.get("max_rounds",null),int(s["round_number"]),MAX_ROUNDS) or not p.get("terminal") is bool:
		return "checkpoint_invalid_simulation_limits"
	if not s.get("combatants") is Array or s["combatants"].is_empty() or s["combatants"].size() > MAX_COMBATANTS or not s.get("events") is Array or s["events"].size() > MAX_EVENTS:
		return "checkpoint_invalid_combatant_or_event_array"
	if not s.get("round_damage_by_target") is Dictionary:
		return "checkpoint_invalid_damage_attribution"
	var roster: Dictionary = {}
	for raw in s["combatants"]:
		if not raw is Dictionary:
			return "checkpoint_invalid_combatant"
		var c: Dictionary = raw
		var id: Variant = c.get("id",null)
		if not id is String or id.is_empty() or id.length() > 160 or roster.has(id) or not c.get("name") is String:
			return "checkpoint_invalid_combatant_id"
		roster[id] = true
		for key in ["level","max_hp","max_mana","max_action_points"]:
			if not _whole(c.get(key,null),1 if key == "level" else 0,1000000000):
				return "checkpoint_invalid_combatant_pool_" + key
		for key in ["hp","mana","action_points","tempo_stun_round","tempo_immunity_until_round"]:
			if not _whole(c.get(key,null),-1000000000,1000000000):
				return "checkpoint_invalid_combatant_counter_" + key
		if int(c["mana"]) < 0 or int(c["mana"]) > int(c["max_mana"]) or int(c["action_points"]) < 0 or int(c["action_points"]) > int(c["max_action_points"]):
			return "checkpoint_invalid_combatant_resource_bounds"
		for key in ["tempo","base_tempo","max_tempo","tempo_regen"]:
			if not _finite(c.get(key,null)):
				return "checkpoint_invalid_tempo"
		if float(c["max_tempo"]) < 0.0 or float(c["base_tempo"]) < 0.0 or float(c["base_tempo"]) > float(c["max_tempo"]) or float(c["tempo_regen"]) < 0.0 or float(c["tempo"]) > float(c["max_tempo"]):
			return "checkpoint_invalid_tempo_bounds"
		for key in ["stats","combat_stats","armour","magic_resists","weapon_skills","weapon_xp","combat_loadout"]:
			if not c.get(key) is Dictionary:
				return "checkpoint_invalid_combatant_" + key
		for key in ["active_effects","effect_immunities"]:
			if not c.get(key) is Array:
				return "checkpoint_invalid_combatant_" + key
		for key in ["one_shot_kill","death_finalized","combat_loadout_locked"]:
			if not c.get(key) is bool:
				return "checkpoint_invalid_combatant_flag"
		if bool(c["death_finalized"]) and int(c["hp"]) > 0 and not bool(c["one_shot_kill"]):
			return "checkpoint_inconsistent_death"
		for raw_effect in c["active_effects"]:
			if not raw_effect is Dictionary:
				return "checkpoint_invalid_effect"
			var effect: Dictionary = raw_effect
			if not effect.get("definition") is Dictionary or not effect.get("effect_id") is String or String(effect["effect_id"]).is_empty():
				return "checkpoint_invalid_effect_definition"
			if not _whole(effect.get("remaining_rounds",null),1,MAX_ROUNDS) or not _whole(effect.get("start_round",null),0,MAX_ROUNDS+1):
				return "checkpoint_invalid_effect_duration"
	if not g.get("teams") is Dictionary or not g.get("active_opponents") is Dictionary or not g.get("engagement_lock_until_round") is Dictionary:
		return "checkpoint_invalid_group"
	var assigned: Dictionary = {}
	for raw_team in Dictionary(g["teams"]).keys():
		var team_id := String(raw_team)
		if team_id.is_empty() or not g["teams"][raw_team] is Array:
			return "checkpoint_invalid_team"
		for raw_id in Array(g["teams"][raw_team]):
			var id := String(raw_id)
			if not roster.has(id) or assigned.has(id):
				return "checkpoint_invalid_team_members"
			assigned[id] = team_id
	for raw_id in Dictionary(g["active_opponents"]).keys():
		var id := String(raw_id)
		var target := String(g["active_opponents"][raw_id])
		if not assigned.has(id) or not assigned.has(target) or String(assigned[id]) == String(assigned[target]):
			return "checkpoint_invalid_active_opponent"
	for raw_id in Dictionary(g["engagement_lock_until_round"]).keys():
		if not roster.has(String(raw_id)) or not _whole(g["engagement_lock_until_round"][raw_id],0,MAX_ROUNDS+3):
			return "checkpoint_invalid_engagement_lock"
	if not e.get("physical_balance") is Dictionary or not e["physical_balance"].get("hit_by_level_difference") is Dictionary or not e["physical_balance"].get("armour_reduction_curve") is Array:
		return "checkpoint_invalid_physical_balance"
	# A newly released EFF catalog must not silently change the remaining
	# ticks or future casts of an interrupted battle from an older version.
	if not e.get("canonical_effects_sha256") is String or String(e["canonical_effects_sha256"]) != JSON.stringify(EffectCatalog.load_json()).sha256_text():
		return "checkpoint_effect_catalog_mismatch"
	var rng: Variant = e.get("rng_state",null)
	if not rng is String or rng.length() > 22 or not rng.is_valid_int() or not _whole(e.get("next_effect_stack_id",null),1,2147483647):
		return "checkpoint_invalid_rng"
	if not o.get("persistent_actions") is Array:
		return "checkpoint_invalid_persistent_actions"
	for raw_action in o["persistent_actions"]:
		if not raw_action is Dictionary or not _whole(Dictionary(raw_action).get("remaining_ticks",null),1,MAX_ROUNDS):
			return "checkpoint_invalid_persistent_action"
		if not roster.has(String(Dictionary(raw_action).get("source_id",""))):
			return "checkpoint_invalid_persistent_source"
	for key in ["definitions","loadouts","cooldowns","cast_rounds"]:
		if not a.get(key) is Dictionary:
			return "checkpoint_invalid_ability_" + key
	for raw_id in Dictionary(a["loadouts"]).keys():
		if not roster.has(String(raw_id)) or not a["loadouts"][raw_id] is Array:
			return "checkpoint_invalid_ability_loadout"
	for raw_id in Dictionary(a["cooldowns"]).keys():
		if not roster.has(String(raw_id)) or not a["cooldowns"][raw_id] is Dictionary:
			return "checkpoint_invalid_ability_cooldown"
		for ability_id in Dictionary(a["cooldowns"][raw_id]).keys():
			if not _whole(a["cooldowns"][raw_id][ability_id],0,MAX_ROUNDS+1000):
				return "checkpoint_invalid_ability_cooldown_round"
	for raw_id in Dictionary(a["cast_rounds"]).keys():
		if not roster.has(String(raw_id)) or not _whole(a["cast_rounds"][raw_id],0,int(s["round_number"])):
			return "checkpoint_invalid_ability_cast_round"
	var seen: Dictionary = {}
	var max_id := 0
	for raw_event in s["events"]:
		if not raw_event is Dictionary:
			return "checkpoint_invalid_event"
		var event: Dictionary = raw_event
		if not _whole(event.get("id",null),1,int(s["next_event_id"])-1) or not _whole(event.get("kind",null),0,3) or not _whole(event.get("parent_event_id",null),-1,int(s["next_event_id"])-1):
			return "checkpoint_invalid_event_id"
		var id := int(event["id"])
		if seen.has(id) or not event.get("payload") is Dictionary or not event.get("result") is Dictionary:
			return "checkpoint_invalid_event_payload"
		if not event.get("source_id") is String or not event.get("target_id") is String:
			return "checkpoint_invalid_event_participants"
		if not _whole(Dictionary(event["payload"]).get("round",null),1,int(s["round_number"])):
			return "checkpoint_invalid_event_round"
		seen[id] = true
		max_id = maxi(max_id,id)
	for raw_event in s["events"]:
		var parent := int(Dictionary(raw_event).get("parent_event_id",-1))
		if parent >= 0 and not seen.has(parent):
			return "checkpoint_orphan_event"
	if int(s["next_event_id"]) <= max_id:
		return "checkpoint_next_event_id_reused"
	return ""

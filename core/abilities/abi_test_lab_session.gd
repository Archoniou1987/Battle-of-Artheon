class_name AbiTestLabSession
extends RefCounted

## Development-only sandbox. Uses the real ABI scheduler, CombatEngine and EFF
## lifecycle but NEVER reads or commits persistent CharacterState resources.
const CASTER_ID := "abi_lab_caster"
const DUMMY_ID := "abi_lab_dummy"
const ALLY_ID := "abi_lab_ally"
const CASTER_PARS := ["PAR030", "PAR033", "PAR035", "PAR125", "PAR126", "PAR150"]
const DUMMY_PARS := ["PAR034", "PAR101", "PAR135", "PAR190", "PAR191", "PAR192", "PAR193", "PAR194", "PAR195", "PAR196"]
const DAMAGE_TYPES := ["slashing", "piercing", "chopping", "blunt", "fire", "water", "air", "earth", "dark", "light"]
const PRESETS := {"ABI003": "Fireball + EFF003", "ABI004": "Healing + EFF004", "LAB_PHYSICAL": "Физическая ABI", "LAB_MAGIC": "Магическая ABI"}

var state: CombatState
var engine: CombatEngine
var orchestrator: RoundOrchestrator
var scheduler: AbilityScheduler
var active_id := ""
var config: Dictionary = {}

static func allowed_pars() -> Dictionary:
	return {"caster": CASTER_PARS.duplicate(), "dummy": DUMMY_PARS.duplicate()}

func reset(settings: Dictionary = {}) -> Dictionary:
	var preset := String(settings.get("preset", "ABI003"))
	if not PRESETS.has(preset):
		return {"ok": false, "reason": "invalid_preset"}
	var damage_type := String(settings.get("damage_type", "fire" if preset != "LAB_PHYSICAL" else "slashing")).to_lower()
	if not DAMAGE_TYPES.has(damage_type):
		return {"ok": false, "reason": "invalid_damage_type"}
	if preset == "LAB_PHYSICAL" and not CombatDamagePayload.is_physical_damage_type(damage_type):
		return {"ok": false, "reason": "physical_type_required"}
	if preset == "LAB_MAGIC" and not CombatDamagePayload.is_magic_damage_type(damage_type):
		return {"ok": false, "reason": "magic_type_required"}
	var raw_damage: Variant = settings.get("damage", 100.0)
	if not RatingMatrix._number(raw_damage) or float(raw_damage) < 0.0 or float(raw_damage) > 100000.0:
		return {"ok": false, "reason": "invalid_damage"}
	var caster_level := clampi(int(settings.get("caster_level", 1)), 1, 100)
	var dummy_level := clampi(int(settings.get("dummy_level", 1)), 1, 100)
	var ability_def: Dictionary = {}
	if preset in ["ABI003", "ABI004"]:
		ability_def = AbilityCatalog.definition(AbilityCatalog.load_json("res://data/abilities/catalog.json"), preset).duplicate(true)
		if ability_def.is_empty():
			return {"ok": false, "reason": "missing_" + preset}
	else:
		ability_def = {
			"name": String(settings.get("name", "Test ability")),
			"delivery_type": "PROJECTILE",
			"target_scope": "SINGLE",
			"uses_magic_hit": preset == "LAB_MAGIC",
			"components": [{"kind": "damage", "amount": float(raw_damage), "damage_type": damage_type}],
			"mana_cost": clampi(int(settings.get("mana_cost", 0)), 0, 1000),
			"cooldown_rounds": clampi(int(settings.get("cooldown_rounds", 0)), 0, 20)
		}
	if not AbilityRuntime.validate_definition(preset, ability_def).is_empty():
		return {"ok": false, "reason": "invalid_ability_definition"}

	var components: Array = ability_def.get("components", [])
	if components.is_empty():
		return {"ok": false, "reason": "missing_damage_component"}
	var primary_damage: Dictionary = Dictionary(components[0]).duplicate(true)
	primary_damage["amount"] = float(raw_damage)
	# Fireball retains its canonical FIRE type and burning EFF003 when edited.
	if not preset in ["ABI003", "ABI004"]:
		primary_damage["damage_type"] = damage_type
	components[0] = primary_damage
	ability_def["components"] = components

	var par_values: Variant = settings.get("par_values", {})
	if not par_values is Dictionary:
		return {"ok": false, "reason": "invalid_par_overrides"}
	for raw_key in par_values:
		var key := String(raw_key)
		var parts := key.split(":")
		if parts.size() != 2:
			return {"ok": false, "reason": "invalid_par_selection", "key": key}
		var allowed: Array = []
		if parts[0] == "caster":
			allowed = CASTER_PARS
		elif parts[0] == "dummy":
			allowed = DUMMY_PARS
		if not allowed.has(parts[1]) or not RatingMatrix._number(par_values[raw_key]):
			return {"ok": false, "reason": "unsupported_or_invalid_PAR", "key": key}

	# A controlled one-roll-per-cast input, never a production combat default.
	var hit_roll := clampi(int(settings.get("hit_roll", 1)), 1, 100)
	var crit_roll := clampi(int(settings.get("crit_roll", 100)), 1, 100)
	ability_def["magic_hit_roll"] = hit_roll
	ability_def["rolls"] = {
		"hit": hit_roll, "magic_hit": hit_roll, "crit": crit_roll,
		"dodge": 100, "auto_block": 100, "block_crush": 100
	}
	config = settings.duplicate(true)
	config["preset"] = preset
	config["damage"] = float(raw_damage)
	config["damage_type"] = "fire" if preset == "ABI003" else ("healing" if preset == "ABI004" else damage_type)
	var target_choice := String(settings.get("target", "ally" if preset == "ABI004" else "dummy"))
	if not target_choice in ["caster", "ally", "dummy"] or (preset == "ABI004" and target_choice == "dummy") or (preset != "ABI004" and target_choice != "dummy"):
		return {"ok": false, "reason": "invalid_target_selection"}
	config["target"] = target_choice
	state = CombatState.new()
	var caster := TestFixtureLoader.new_combatant(CASTER_ID, "ABI Lab", caster_level, 10000, 500)
	var dummy := TestFixtureLoader.new_combatant(DUMMY_ID, "Манекен", dummy_level, 10000, 0)
	var ally := TestFixtureLoader.new_combatant(ALLY_ID, "Союзник", caster_level, 10000, 0)
	if preset == "ABI004":
		var starting_hp := clampi(int(settings.get("initial_hp", 5000)), 1, 10000)
		caster.hp = starting_hp
		ally.hp = starting_hp
	state.add_combatant(caster)
	state.add_combatant(dummy)
	state.add_combatant(ally)
	for raw_key in par_values:
		var parts := String(raw_key).split(":")
		var combatant := caster if parts[0] == "caster" else dummy
		if not _set_par(combatant, String(parts[1]), float(par_values[raw_key])):
			return {"ok": false, "reason": "invalid_PAR", "key": String(raw_key)}
	dummy.armour = PhysicalArmourService.assemble({}, dummy.combat_stats["par_totals"])
	if not bool(ParCombatContract.validate(caster).get("ok", false)) or not bool(ParCombatContract.validate(dummy).get("ok", false)):
		return {"ok": false, "reason": "invalid_par_contract"}
	engine = CombatEngine.new(state)
	engine.combat_rng.seed = 13003
	orchestrator = RoundOrchestrator.new(state, engine)
	active_id = preset
	scheduler = AbilityScheduler.new({preset: ability_def}, {CASTER_ID: [preset]})
	return {"ok": true, "ability_id": preset, "damage": float(raw_damage), "damage_type": config["damage_type"]}

func next_round(cast_ability: bool = true) -> Dictionary:
	if state == null or scheduler == null or orchestrator == null:
		return {"ok": false, "reason": "lab_not_initialized"}
	if state.get_combatant(DUMMY_ID).is_death_finalized() or state.get_combatant(CASTER_ID).is_death_finalized():
		return {"ok": false, "reason": "lab_battle_finished"}
	var caster := state.get_combatant(CASTER_ID)
	var dummy := state.get_combatant(DUMMY_ID)
	var selected_target := String(config.get("target", "dummy"))
	var target_id := CASTER_ID if selected_target == "caster" else (ALLY_ID if selected_target == "ally" else DUMMY_ID)
	var target := state.get_combatant(target_id)
	var hp_before := target.visible_hp()
	var mana_before := caster.mana
	var event_start := state.event_log.size()
	orchestrator.begin_round()
	var cast_status := "skip"
	var ability_event_id := -1
	if cast_ability:
		var cooldowns: Dictionary = scheduler.cooldowns_by_combatant.get(CASTER_ID, {})
		var definition: Dictionary = AbilityCatalog.definition(scheduler.definitions, active_id)
		if not AbilityRuntime.can_use(active_id, cooldowns, state.round_number):
			cast_status = "cooldown"
		elif caster.mana < int(definition.get("mana_cost", 0)):
			cast_status = "insufficient_mana"
		else:
			var event := scheduler.cast_event(state, CASTER_ID, target_id, active_id)
			if event == null:
				cast_status = "rejected"
			else:
				cast_status = "cast"
				ability_event_id = event.event_id
				state.queue_event(event)
				engine.resolve_pending_events()
	var summary: Dictionary = orchestrator.end_round()
	var events: Array[Dictionary] = []
	var report: Array[String] = []
	for index in range(event_start, state.event_log.size()):
		var event: CombatEvent = state.event_log[index]
		var kind: String = String(["ACTION", "ATTACK", "DAMAGE", "EFFECT"][int(event.kind)])
		var detail := {"id": event.event_id, "parent_id": event.parent_event_id, "kind": kind,
			"payload": event.payload.duplicate(true), "result": event.result.duplicate(true)}
		events.append(detail)
		report.append(_event_description(event, kind))
	var effects: Array[Dictionary] = []
	for active in target.active_effects:
		effects.append({"effect_id": String(active.get("effect_id", "")),
			"stacks": int(active.get("stacks", 1)),
			"remaining_rounds": int(active.get("remaining_rounds", 0))})
	return {
		"ok": true, "round": state.round_number, "cast_status": cast_status,
		"ability_id": active_id, "ability_event_id": ability_event_id,
		"mana_before": mana_before, "mana_after": caster.mana,
		"hp_before": hp_before, "hp_after": target.visible_hp(),
		"target_id":target_id, "target_name":target.display_name,
		"damage_dealt": hp_before - target.visible_hp(),
		"healing_done": target.visible_hp() - hp_before, "effects": effects,
		"events": events, "report": report,
		"battle_outcome": String(summary.get("battle_outcome", "ongoing"))
	}

func _set_par(combatant: CombatantState, id: String, value: float) -> bool:
	if not is_finite(value) or value < 0.0 or value > 100000.0:
		return false
	var totals: Dictionary = combatant.combat_stats["par_totals"]
	totals[id] = value
	if ParCombatContract.RATINGS.has(id):
		var key := String(ParCombatContract.RATINGS[id])
		combatant.combat_stats[key] = value
		combatant.combat_stats[key + "_percent"] = RatingMatrix.to_percent(value, combatant.level)
	elif id == "PAR125":
		combatant.combat_stats["armour_penetration_flat"] = value
	elif id == "PAR126":
		combatant.combat_stats["armour_penetration_percent"] = value
	elif id == "PAR135":
		combatant.combat_stats["damage_reduction_pct"] = value
	return true

static func _event_description(event: CombatEvent, kind: String) -> String:
	var result: Dictionary = event.result
	var payload: Dictionary = event.payload
	match kind:
		"ACTION":
			return "ACTION #%d %s: %s | magic roll %s" % [event.event_id, String(payload.get("ability_id", "")), String(result.get("outcome", "-")), str(result.get("magic_hit_roll", "-"))]
		"ATTACK":
			return "ATTACK #%d: %s | hit %s vs %.1f%% | crit %s | raw %.2f | armour %.2f | after armour %.2f" % [
				event.event_id, String(result.get("outcome", "-")), str(result.get("hit_roll", "-")),
				float(result.get("hit_chance", 0.0)), str(result.get("critical", false)),
				float(result.get("raw_damage", 0.0)), float(result.get("effective_armour", 0.0)),
				float(result.get("after_armour_damage", result.get("raw_damage", 0.0)))]
		"DAMAGE":
			return "DAMAGE #%d: %s | input %.2f | magic resist %.1f%% | damage reduction %.1f%% | HP -%d" % [
				event.event_id, String(payload.get("damage_type", "")), float(payload.get("amount", 0.0)),
				float(result.get("magic_resist", 0.0)) * 100.0,
				float(result.get("damage_reduction", 0.0)) * 100.0,
				int(result.get("hp_removed", 0))]
		"EFFECT":
			return "EFF #%d: %s | applied=%s | chance %.1f%% | %s" % [
				event.event_id, String(result.get("effect_id", payload.get("effect_id", ""))),
				str(result.get("resolved", false)), float(result.get("effective_chance", 100.0)),
				String(result.get("outcome", "applied"))] + (" | healed %d" % int(result.get("healed", 0)) if result.has("healed") else "")
	return kind

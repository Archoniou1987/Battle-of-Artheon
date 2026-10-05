class_name CombatEngine
extends RefCounted

var state: CombatState
var physical_balance: Dictionary

func _init(combat_state: CombatState, balance: Dictionary = {}) -> void:
	state = combat_state
	physical_balance = balance

func resolve_pending_events() -> void:
	while not state.pending_events.is_empty():
		var event: CombatEvent = state.pending_events.pop_front()
		resolve_event(event)

func resolve_event(event: CombatEvent) -> void:
	match event.kind:
		CombatEvent.Kind.ATTACK: _resolve_attack(event)
		CombatEvent.Kind.DAMAGE: _resolve_damage(event)
		CombatEvent.Kind.EFFECT: _resolve_effect(event)
	state.record_event(event)

func _resolve_attack(event: CombatEvent) -> void:
	var attacker := state.get_combatant(event.source_id)
	var defender := state.get_combatant(event.target_id)
	if attacker == null or defender == null:
		event.set_result("outcome", "invalid_combatant"); return
	var rolls: Dictionary = event.payload.get("rolls", {})
	var hit_chance := _hit_chance(attacker.level - defender.level) + float(attacker.combat_stats.get("hit_modifier", 0.0))
	if not CombatMath.roll_success(hit_chance, int(rolls.get("hit", 100))):
		event.set_result("outcome", "miss"); _gain_basic_attack_ap(attacker, event); return
	var active_defence_available := _active_defence_available(defender.tempo, int(rolls.get("reaction", 100)))
	if active_defence_available:
		var dodge := CombatMath.effective_dodge(float(defender.combat_stats.get("dodge", 0.0)), float(attacker.combat_stats.get("anti_dodge", 0.0)))
		if CombatMath.roll_success(dodge, int(rolls.get("dodge", 100))):
			event.set_result("outcome", "dodge"); _queue_counterattack(event, defender, attacker, rolls); _gain_basic_attack_ap(attacker, event); return
		if _manual_block_success(event, defender):
			if not _block_crushed(attacker, rolls):
				event.set_result("outcome", "manual_block")
				_trigger_manual_block_effects(event, defender, rolls)
				_gain_basic_attack_ap(attacker, event); return
		var auto_block := float(defender.combat_stats.get("auto_block", 0.0))
		if CombatMath.roll_success(auto_block, int(rolls.get("auto_block", 100))):
			if not _block_crushed(attacker, rolls):
				event.set_result("outcome", "auto_block"); _gain_basic_attack_ap(attacker, event); return

	var active_crit_bonus := _active_effect_value(attacker, "crit_bonus")
	var crit := CombatMath.effective_crit(float(attacker.combat_stats.get("crit", 0.0)) + active_crit_bonus, float(defender.combat_stats.get("anti_crit", 0.0)))
	var is_crit := CombatMath.roll_success(crit, int(rolls.get("crit", 100)))
	var raw_damage := float(event.payload.get("raw_damage", 0.0))
	if is_crit: raw_damage *= float(physical_balance.get("crit_damage_multiplier", 1.5))
	var zone := String(event.payload.get("zone", "chest")); var damage_type := String(event.payload.get("damage_type", "slashing"))
	var effective_armour := CombatMath.effective_armour(_armour_for(defender, zone, damage_type), float(attacker.combat_stats.get("flat_armour_pen", 0.0)), float(attacker.combat_stats.get("percent_armour_reduction", 0.0)))
	var reduction := BalanceCurve.sample(physical_balance.get("armour_reduction_curve", []), effective_armour)
	var after_armour := raw_damage * (1.0 - clampf(reduction, 0.0, 1.0))
	var damage_event := state.create_event(CombatEvent.Kind.DAMAGE, event.source_id, event.target_id, {"amount": after_armour, "damage_type": damage_type, "zone": zone, "source": "attack"}, event.event_id)
	state.queue_event(damage_event)
	event.set_result("outcome", "connected"); event.set_result("critical", is_crit); event.set_result("raw_damage", raw_damage); event.set_result("damage_event_id", damage_event.event_id)
	_trigger_weapon_on_hit(event, attacker, defender, rolls)
	_gain_basic_attack_ap(attacker, event)

func _resolve_damage(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	if target == null: event.set_result("error", "target_not_found"); return
	var amount := float(event.payload.get("amount", 0.0))
	amount *= 1.0 - clampf(_active_effect_value(target, "damage_reduction"), 0.0, 1.0)
	var final_damage := CombatMath.final_damage_floor(amount)
	var applied := target.apply_damage(final_damage)
	event.set_result("final_damage", final_damage); event.set_result("hp_removed", applied); event.set_result("connected", true)

func _resolve_effect(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	var effect_id := String(event.payload.get("effect_id", ""))
	var definition := _effect_definition(effect_id)
	if target == null or definition.is_empty(): event.set_result("resolved", false); return
	var kind := String(definition.get("kind", ""))
	if kind == "heal":
		event.set_result("healed", target.restore_hp(int(definition.get("amount", 0))))
	else:
		_apply_timed_effect(target, effect_id, definition, event.source_id)
	event.set_result("effect_id", effect_id); event.set_result("resolved", true)

func _trigger_weapon_on_hit(parent: CombatEvent, attacker: CombatantState, defender: CombatantState, rolls: Dictionary) -> void:
	var effects: Array = attacker.combat_stats.get("weapon_on_hit_effects", [])
	if effects.is_empty(): return
	var index := clampi(int(parent.payload.get("weapon_index", 0)), 0, effects.size() - 1)
	var trigger: Dictionary = effects[index]
	if trigger.is_empty(): return
	if CombatMath.roll_success(float(trigger.get("chance", 0.0)), int(rolls.get("on_hit_effect", 100))):
		state.queue_event(state.create_event(CombatEvent.Kind.EFFECT, attacker.combatant_id, defender.combatant_id if String(trigger.get("effect_id")) == "EFF001" else attacker.combatant_id, {"effect_id": String(trigger.get("effect_id", ""))}, parent.event_id))

func _trigger_manual_block_effects(parent: CombatEvent, defender: CombatantState, rolls: Dictionary) -> void:
	var triggers: Array = defender.combat_stats.get("on_manual_block_effects", [])
	for trigger in triggers:
		if CombatMath.roll_success(float(trigger.get("chance", 0.0)), int(rolls.get("manual_block_effect", 100))):
			state.queue_event(state.create_event(CombatEvent.Kind.EFFECT, defender.combatant_id, defender.combatant_id, {"effect_id": String(trigger.get("effect_id", ""))}, parent.event_id))

func _apply_timed_effect(target: CombatantState, effect_id: String, definition: Dictionary, source_id: String) -> void:
	var max_stacks := int(definition.get("max_stacks", 1)); var count := 0
	for active in target.active_effects:
		if String(active.get("effect_id", "")) == effect_id: count += 1
	if count >= max_stacks: return
	target.active_effects.append({"effect_id":effect_id,"definition":definition.duplicate(true),"source_id":source_id,"start_round":state.round_number + 1,"remaining_rounds":int(definition.get("duration_rounds", 1))})

func _active_effect_value(target: CombatantState, field: String) -> float:
	var total := 0.0
	for active in target.active_effects:
		if state.round_number >= int(active.get("start_round", 999999)) and int(active.get("remaining_rounds", 0)) > 0:
			total += float(active.get("definition", {}).get(field, 0.0))
	return total

func _effect_definition(effect_id: String) -> Dictionary:
	return physical_balance.get("effects", {}).get(effect_id, {})

func _queue_counterattack(parent: CombatEvent, defender: CombatantState, attacker: CombatantState, rolls: Dictionary) -> void:
	if bool(parent.payload.get("is_counterattack", false)): return
	var chance := float(defender.combat_stats.get("counterattack", 0.0))
	if not CombatMath.roll_success(chance, int(rolls.get("counterattack", 100))): return
	var child := state.create_event(CombatEvent.Kind.ATTACK, defender.combatant_id, attacker.combatant_id, {"raw_damage":float(defender.combat_stats.get("main_hand_damage",0.0))*float(physical_balance.get("counterattack_damage_coefficient",0.8)),"zone":String(parent.payload.get("counterattack_zone","chest")),"damage_type":String(defender.combat_stats.get("main_hand_damage_type","slashing")),"rolls":parent.payload.get("counterattack_rolls",{}),"is_counterattack":true,"generates_ap":false,"weapon_index":0}, parent.event_id)
	state.queue_event(child); parent.set_result("counterattack_event_id", child.event_id)

func _gain_basic_attack_ap(attacker: CombatantState, event: CombatEvent) -> void:
	if bool(event.payload.get("generates_ap", true)) and not bool(event.payload.get("is_counterattack", false)) and not bool(event.payload.get("is_extra_attack", false)):
		event.set_result("ap_gained", attacker.gain_action_points(int(physical_balance.get("basic_physical_attack_ap_gain", 1))))

func _hit_chance(level_difference: int) -> float:
	var table: Dictionary = physical_balance.get("hit_by_level_difference", {})
	if table.is_empty(): return 95.0
	return float(table.get(str(clampi(level_difference, -10, 5)), 95.0))
func _active_defence_available(tempo: float, roll: int) -> bool:
	if tempo <= -100.0: return false
	if tempo >= 0.0: return true
	return CombatMath.roll_success(100.0 + tempo, roll)
func _manual_block_success(event: CombatEvent, defender: CombatantState) -> bool:
	var attack_zone := String(event.payload.get("zone", "")); var chosen_zones: Array = defender.combat_stats.get("manual_block_zones", [])
	if chosen_zones.has(attack_zone): return true
	var legacy_zone := String(defender.combat_stats.get("manual_block_zone", "")); return not legacy_zone.is_empty() and legacy_zone == attack_zone
func _block_crushed(attacker: CombatantState, rolls: Dictionary) -> bool:
	return CombatMath.roll_success(float(attacker.combat_stats.get("block_crush", 0.0)), int(rolls.get("block_crush", 100)))
func _armour_for(defender: CombatantState, zone: String, damage_type: String) -> float:
	var zone_armour: Dictionary = defender.armour.get(zone, {}); return float(zone_armour.get(damage_type, 0.0))

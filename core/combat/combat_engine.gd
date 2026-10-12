class_name CombatEngine
extends RefCounted

var state: CombatState
var physical_balance: Dictionary
var _next_effect_stack_id: int = 1
var group_state:GroupCombatState
var zone_state:CombatZoneState

const HIT_ZONES:=["head","chest","arms","waist","legs"]

func configure_spatial_context(groups:GroupCombatState,zones:CombatZoneState)->void:
	group_state=groups
	zone_state=zones

func _init(combat_state: CombatState, balance: Dictionary = {}) -> void:
	state = combat_state
	physical_balance = balance

func resolve_pending_events() -> void:
	while not state.pending_events.is_empty():
		var event: CombatEvent = state.pending_events.pop_front()
		resolve_event(event)

func resolve_event(event: CombatEvent) -> void:
	match event.kind:
		CombatEvent.Kind.ACTION: _resolve_action(event)
		CombatEvent.Kind.ATTACK: _resolve_attack(event)
		CombatEvent.Kind.DAMAGE: _resolve_damage(event)
		CombatEvent.Kind.EFFECT: _resolve_effect(event)
	state.record_event(event)

func _resolve_action(event: CombatEvent) -> void:
	var source := state.get_combatant(event.source_id)
	if source == null:
		event.set_result("outcome", "invalid_combatant")
		return
	var target_ids := _valid_action_targets(event)
	if target_ids.is_empty():
		event.set_result("outcome", "invalid_combatant")
		return
	var child_event_ids:Array[int] = []
	var unsupported_components:Array[String] = []
	# Magic AREA/CHAIN is one cast roll, not one independent roll per victim.
	var shared_magic_roll:=bool(event.payload.get("uses_magic_hit",false)) and String(event.payload.get("delivery_type","DIRECT")) in ["AREA","CHAIN"]
	if shared_magic_roll and not _magic_hit_success(event,String(target_ids[0])):
		event.set_result("outcome","magic_miss")
		event.set_result("child_event_ids",[])
		event.set_result("resolved_target_ids",[])
		return
	for raw_component in event.payload.get("components", []):
		if not raw_component is Dictionary:
			unsupported_components.append("invalid")
			continue
		var component:Dictionary = raw_component
		var kind := String(component.get("kind", ""))
		if not ["damage","effect","heal"].has(kind):
			unsupported_components.append(kind if not kind.is_empty() else "unknown")
			continue
		var scale := _aoe_component_scale(component, target_ids.size())
		for target_id in target_ids:
			if not shared_magic_roll and not _magic_hit_success(event,String(target_id)):
				continue
			var child := _make_action_component_event(event, component, String(target_id), scale)
			if child != null:
				state.queue_event(child)
				child_event_ids.append(child.event_id)
	var has_supported_components:bool=unsupported_components.size()<Array(event.payload.get("components",[])).size()
	var outcome:="dispatched" if not child_event_ids.is_empty() else ("magic_miss" if bool(event.payload.get("uses_magic_hit",false)) and has_supported_components else "no_supported_components")
	event.set_result("outcome", outcome)
	event.set_result("child_event_ids", child_event_ids)
	event.set_result("dispatched_component_count", child_event_ids.size())
	event.set_result("unsupported_components", unsupported_components)
	event.set_result("resolved_target_ids", target_ids)

func _valid_action_targets(event:CombatEvent) -> Array[String]:
	var result:Array[String]=[]
	var raw_targets:Array=event.payload.get("target_ids",[event.target_id])
	var target_zone_id:=int(event.payload.get("target_zone_id",-1))
	if zone_state!=null and target_zone_id>=CombatZoneState.MIN_ZONE and target_zone_id<=CombatZoneState.MAX_ZONE:
		raw_targets=zone_state.occupants(target_zone_id)
	var source_team:=group_state.team_of(event.source_id) if group_state!=null else ""
	var support_action:=_action_is_support(event)
	var reach_definition:Dictionary={
		"min_zone_distance":int(event.payload.get("min_zone_distance",0)),
		"max_zone_distance":int(event.payload.get("max_zone_distance",2 if String(event.payload.get("delivery_type","DIRECT"))!="MELEE" else 0)),
		"two_zone_hit_modifier":float(event.payload.get("two_zone_hit_modifier",-50.0))
	}
	for raw_id in raw_targets:
		var target_id:=String(raw_id)
		if target_id.is_empty() or result.has(target_id):
			continue
		var target:=state.get_combatant(target_id)
		if target==null or target.is_death_finalized():
			continue
		if group_state!=null:
			var same_team:=group_state.team_of(target_id)==source_team
			if support_action!=same_team:
				continue
		if zone_state!=null:
			var d:=zone_state.distance(event.source_id,target_id)
			if d<0 or not CombatReachPolicy.can_reach(d,int(reach_definition.min_zone_distance),int(reach_definition.max_zone_distance)):
				continue
		result.append(target_id)
	return result

func _action_is_support(event:CombatEvent)->bool:
	var has_offense:=false
	var has_support:=false
	for raw_component in event.payload.get("components",[]):
		if not raw_component is Dictionary:
			continue
		var kind:=String(raw_component.get("kind",""))
		if kind=="heal":
			has_support=true
		elif kind in ["damage","effect"]:
			has_offense=true
	return has_support and not has_offense

func _distance_modifier(event:CombatEvent,target_id:String)->float:
	if zone_state==null:
		return 0.0
	var d:=-1
	if event.payload.has("target_zone_id"):
		var source_zone:=zone_state.zone_of(event.source_id)
		var target_zone:=int(event.payload.get("target_zone_id",-1))
		if source_zone>=CombatZoneState.MIN_ZONE and target_zone>=CombatZoneState.MIN_ZONE and target_zone<=CombatZoneState.MAX_ZONE:
			d=absi(target_zone-source_zone)
	if d<0:
		d=zone_state.distance(event.source_id,target_id)
	return CombatReachPolicy.distance_hit_modifier(d,event.payload)

func _magic_hit_success(event:CombatEvent,target_id:String)->bool:
	if not bool(event.payload.get("uses_magic_hit",false)):
		return true
	var source:=state.get_combatant(event.source_id)
	if source==null:
		return false
	var chance:=CombatModifierService.combat_chance(source, "magic_hit_rating", "magic_hit", state.round_number, 95.0)+float(event.payload.get("magic_hit_modifier",0.0))+_distance_modifier(event,target_id)
	return CombatMath.roll_success(clampf(chance,0.0,100.0),int(event.payload.get("magic_hit_roll",1)))

func _aoe_component_scale(component:Dictionary, target_count:int) -> float:
	if target_count <= 0:
		return 0.0
	var full_targets := int(component.get("full_targets", 0))
	if full_targets <= 0:
		return 1.0
	return minf(1.0, float(full_targets) / float(target_count))

func _make_action_component_event(parent:CombatEvent, component:Dictionary, target_id:String, scale:float) -> CombatEvent:
	var kind := String(component.get("kind", ""))
	var delivery_type := String(parent.payload.get("delivery_type", "DIRECT"))
	if kind=="heal":
		return state.create_event(CombatEvent.Kind.EFFECT,parent.source_id,target_id,{
			"inline_heal":int(round(float(component.get("amount",0.0))*scale)),
			"source_type":"ability",
			"ability_id":String(parent.payload.get("ability_id","")),
			"delivery_type":delivery_type,
			"aoe_scale":scale
		},parent.event_id)
	if kind == "damage":
		var damage_type := String(component.get("damage_type", "physical"))
		var amount := float(component.get("amount", 0.0))
		# ABI magic damage uses the attacker's canonical rating percentage plus
		# active EFF overlays. Physical ABI and periodic EFF are unchanged.
		if _is_magic_damage_type(damage_type):
			var caster := state.get_combatant(parent.source_id)
			if caster != null:
				var flat_bonus := CombatModifierService.effective_stat(caster, "magic_damage_flat", state.round_number)
				var bonus_percent := CombatModifierService.effective_percent(caster, "magic_damage_rating", state.round_number)
				# Magic damage rating and direct percentage bonuses use one overlay.
				amount = maxf(0.0, amount + flat_bonus) * maxf(0.0, 1.0 + bonus_percent / 100.0)
		amount *= scale
		if delivery_type in ["MELEE", "PROJECTILE"]:
			return state.create_event(CombatEvent.Kind.ATTACK, parent.source_id, target_id, {
				"raw_damage": amount,
				"damage_type": damage_type,
				"zone": String(component.get("zone", parent.payload.get("zone", "chest"))),
				"rolls": parent.payload.get("rolls", {}),
				"source": "ability",
				"source_kind": "ability",
				"ability_id": String(parent.payload.get("ability_id", "")),
				"delivery_type": delivery_type,
				"min_zone_distance": int(parent.payload.get("min_zone_distance", 0)),
				"max_zone_distance": int(parent.payload.get("max_zone_distance", 2)),
				"two_zone_hit_modifier": float(parent.payload.get("two_zone_hit_modifier", -50.0)),
				"uses_physical_block": damage_type in ["physical", "slashing", "piercing", "chopping", "blunt"],
				"bypass_physical_mitigation": not damage_type in ["physical", "slashing", "piercing", "chopping", "blunt"],
				"generates_ap": false,
				"aoe_scale": scale
			}, parent.event_id)
		return state.create_event(CombatEvent.Kind.DAMAGE, parent.source_id, target_id, {
			"amount": amount,
			"raw_damage": amount,
			"damage_type": damage_type,
			"source": "ability",
			"ability_id": String(parent.payload.get("ability_id", "")),
			"delivery_type": delivery_type,
			"aoe_scale": scale
		}, parent.event_id)
	if kind == "effect":
		return state.create_event(CombatEvent.Kind.EFFECT, parent.source_id, target_id, {
			"effect_id": String(component.get("effect_id", "")),
			"base_chance": float(component.get("base_chance", 100.0)) * scale,
			"unscaled_base_chance": float(component.get("base_chance", 100.0)),
			"resist_type": String(component.get("resist_type", component.get("element", ""))),
			"effect_roll": int(component.get("effect_roll", parent.payload.get("effect_roll", 1))),
			"source_type": "ability",
			"ability_id": String(parent.payload.get("ability_id", "")),
			"delivery_type": delivery_type,
			"aoe_scale": scale
		}, parent.event_id)
	return null

func _resolve_attack(event: CombatEvent) -> void:
	var attacker := state.get_combatant(event.source_id)
	var defender := state.get_combatant(event.target_id)
	if attacker == null or defender == null:
		event.set_result("outcome", "invalid_combatant"); return
	var rolls: Dictionary = event.payload.get("rolls", {})
	var uses_magic_hit:=bool(event.payload.get("uses_magic_hit",false))
	var distance_hit_modifier:=_distance_modifier(event,event.target_id) if uses_magic_hit else _physical_ranged_distance_hit_modifier(event)
	var is_weapon_attack:=bool(event.payload.get("is_weapon_attack",event.payload.has("weapon_index") and String(event.payload.get("source_kind",""))!="ability"))
	var weapon_skill_penalty:=0.0 if uses_magic_hit or not is_weapon_attack else _weapon_skill_hit_penalty(attacker, int(event.payload.get("weapon_index",0)))
	var hit_chance:=CombatModifierService.combat_chance(attacker, "magic_hit_rating", "magic_hit", state.round_number, 95.0)+float(event.payload.get("magic_hit_modifier",0.0))+distance_hit_modifier if uses_magic_hit else _hit_chance(attacker.level - defender.level) + float(attacker.combat_stats.get("hit_modifier", 0.0)) - weapon_skill_penalty + distance_hit_modifier
	event.set_result("distance_hit_modifier",distance_hit_modifier)
	event.set_result("weapon_skill_hit_penalty",weapon_skill_penalty)
	event.set_result("hit_system","magic" if uses_magic_hit else "physical")
	var hit_roll:=int(event.payload.get("magic_hit_roll",rolls.get("magic_hit",1))) if uses_magic_hit else int(rolls.get("hit",100))
	if not CombatMath.roll_success(clampf(hit_chance,0.0,100.0),hit_roll):
		event.set_result("outcome", "magic_miss" if uses_magic_hit else "miss"); _gain_basic_attack_ap(attacker, event); return
	var active_defence_available := not uses_magic_hit and not _effect_flag(defender, "active_defence_locked") and _active_defence_available(defender.tempo + _active_effect_value(defender, "tempo_modifier"), int(rolls.get("reaction", 100)))
	if active_defence_available:
		var dodge := CombatMath.effective_dodge(CombatModifierService.combat_chance(defender, "dodge_rating", "dodge", state.round_number), CombatModifierService.combat_chance(attacker, "anti_dodge_rating", "anti_dodge", state.round_number))
		if CombatMath.roll_success(dodge, int(rolls.get("dodge", 100))):
			event.set_result("outcome", "dodge"); _queue_counterattack(event, defender, attacker, rolls); _gain_basic_attack_ap(attacker, event); return
		if _event_uses_physical_block(event) and _manual_block_success(event, defender):
			if not _block_crushed(attacker, rolls):
				event.set_result("outcome", "manual_block")
				_trigger_manual_block_effects(event, defender, rolls)
				_gain_basic_attack_ap(attacker, event); return
		var auto_block := float(defender.combat_stats.get("auto_block", 0.0))
		if _event_uses_physical_block(event) and defender.can_auto_block() and CombatMath.roll_success(auto_block, int(rolls.get("auto_block", 100))):
			if not _block_crushed(attacker, rolls):
				event.set_result("outcome", "auto_block"); _gain_basic_attack_ap(attacker, event); return

	if bool(event.payload.get("bypass_physical_mitigation", false)):
		var ability_damage := state.create_event(CombatEvent.Kind.DAMAGE, event.source_id, event.target_id, {
			"amount": float(event.payload.get("raw_damage", 0.0)),
			"raw_damage": float(event.payload.get("raw_damage", 0.0)),
			"damage_type": String(event.payload.get("damage_type", "physical")),
			"source": "ability",
			"ability_id": String(event.payload.get("ability_id", "")),
			"delivery_type": String(event.payload.get("delivery_type", "PROJECTILE"))
		}, event.event_id)
		state.queue_event(ability_damage)
		event.set_result("outcome", "connected")
		event.set_result("damage_event_id", ability_damage.event_id)
		# Non-physical weapon attacks still complete the weapon pipeline.
		if is_weapon_attack:
			_trigger_weapon_on_hit(event, attacker, defender, rolls)
		_gain_basic_attack_ap(attacker, event)
		return

	var active_crit_bonus := _active_effect_value(attacker, "crit_bonus")
	var crit := CombatMath.effective_crit(CombatModifierService.combat_chance(attacker, "crit_chance_rating", "crit", state.round_number) + active_crit_bonus, CombatModifierService.combat_chance(defender, "anti_crit_rating", "anti_crit", state.round_number))
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
	if is_weapon_attack:
		_trigger_weapon_on_hit(event, attacker, defender, rolls)
	_gain_basic_attack_ap(attacker, event)

func _resolve_damage(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	if target == null: event.set_result("error", "target_not_found"); return
	var amount := float(event.payload.get("amount", 0.0))
	var damage_type := String(event.payload.get("damage_type", ""))
	var magic_resist := _magic_resist(target, damage_type)
	if _is_magic_damage_type(damage_type):
		amount *= 1.0 - magic_resist
		event.set_result("magic_resist", magic_resist)
	# One mitigation stage for permanent reduction and active defensive EFF.
	# Values are fractions (0.75 = 75%); the total cannot exceed 100%.
	var permanent_reduction := float(target.combat_stats.get("damage_reduction", 0.0))
	var temporary_reduction := _active_effect_value(target, "damage_reduction")
	var total_reduction := clampf(permanent_reduction + temporary_reduction, 0.0, 1.0)
	amount *= 1.0 - total_reduction
	event.set_result("damage_reduction", total_reduction)
	var final_damage := CombatMath.final_damage_floor(amount)
	var hp_before := target.hp
	var applied := target.apply_damage(final_damage)
	state.record_damage(event.target_id,event.source_id,final_damage)
	event.set_result("final_damage", final_damage)
	event.set_result("hp_removed", applied)
	event.set_result("hp_before", hp_before)
	event.set_result("hp_after", target.hp)
	event.set_result("visible_hp_after", target.visible_hp())
	event.set_result("connected", true)

func _resolve_effect(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	if target==null:
		event.set_result("resolved",false)
		return
	if event.payload.has("inline_heal"):
		var healed:=target.restore_hp(int(event.payload.get("inline_heal",0)))
		event.set_result("healed",healed)
		event.set_result("resolved",healed!=0)
		return
	var effect_id := String(event.payload.get("effect_id", ""))
	var definition := _effect_definition(effect_id)
	if definition.is_empty(): event.set_result("resolved", false); return
	var effect_kind := String(definition.get("kind", ""))
	if target.effect_immunities.has(effect_id) or target.effect_immunities.has(effect_kind):
		event.set_result("effect_id", effect_id)
		event.set_result("resolved", false)
		event.set_result("outcome", "immune")
		return
	var base_chance := clampf(float(event.payload.get("base_chance", 100.0)), 0.0, 100.0)
	var resist_type := String(event.payload.get("resist_type", ""))
	var resist := _magic_resist(target, resist_type)
	var effective_chance := base_chance * (1.0 - resist)
	event.set_result("base_chance", base_chance)
	event.set_result("resist", resist)
	event.set_result("effective_chance", effective_chance)
	if not CombatMath.roll_success(effective_chance, int(event.payload.get("effect_roll", 1))):
		event.set_result("effect_id", effect_id)
		event.set_result("resolved", false)
		event.set_result("outcome", "resisted")
		return
	var kind := effect_kind
	if kind == "heal":
		event.set_result("healed", target.restore_hp(int(definition.get("amount", 0))))
	else:
		_apply_timed_effect(target, effect_id, definition, event)
	event.set_result("effect_id", effect_id); event.set_result("resolved", true)

func _trigger_weapon_on_hit(parent: CombatEvent, attacker: CombatantState, defender: CombatantState, rolls: Dictionary) -> void:
	var effects:Array=attacker.combat_stats.get("weapon_on_hit_effects",[])
	if effects.is_empty(): return
	var attack_weapon_index:=int(parent.payload.get("weapon_index",0))
	var per_source_rolls:Array=rolls.get("on_hit_effects",[])
	var eligible_index:=0
	for raw_trigger in effects:
		var trigger:Dictionary=raw_trigger
		if trigger.is_empty(): continue
		var source_weapon_index:=int(trigger.get("weapon_index",-1))
		if source_weapon_index>=0 and source_weapon_index!=attack_weapon_index:
			continue
		var roll:=int(per_source_rolls[eligible_index]) if eligible_index<per_source_rolls.size() else int(rolls.get("on_hit_effect",100))
		eligible_index+=1
		if not CombatMath.roll_success(float(trigger.get("chance",0.0)),roll):
			continue
		var payload:={"effect_id":String(trigger.get("effect_id","")),"source_type":String(trigger.get("source_type","item")),"source_instance_id":String(trigger.get("source_instance_id",""))}
		state.queue_event(state.create_event(CombatEvent.Kind.EFFECT,attacker.combatant_id,defender.combatant_id if String(trigger.get("effect_id"))=="EFF001" else attacker.combatant_id,payload,parent.event_id))

func _trigger_manual_block_effects(parent: CombatEvent, defender: CombatantState, rolls: Dictionary) -> void:
	var triggers: Array = defender.combat_stats.get("on_manual_block_effects", [])
	for trigger in triggers:
		if CombatMath.roll_success(float(trigger.get("chance", 0.0)), int(rolls.get("manual_block_effect", 100))):
			var payload := {"effect_id":String(trigger.get("effect_id", "")),"source_type":String(trigger.get("source_type", "item")),"source_instance_id":String(trigger.get("source_instance_id", ""))}
			state.queue_event(state.create_event(CombatEvent.Kind.EFFECT, defender.combatant_id, defender.combatant_id, payload, parent.event_id))

func _apply_timed_effect(target: CombatantState, effect_id: String, definition: Dictionary, event: CombatEvent) -> void:
	var stacking := String(definition.get("stacking", "unique"))
	var max_stacks := maxi(1, int(definition.get("max_stacks", 1)))
	var matching:Array = []
	for active in target.active_effects:
		if String(active.get("effect_id", "")) == effect_id: matching.append(active)
	var record := _make_effect_record(effect_id, definition, event)
	if stacking == "stack":
		if matching.size() < max_stacks: target.active_effects.append(record)
		return
	# UNIQUE means one logical buff/debuff per target. Reapplication replaces it.
	for active in matching: target.active_effects.erase(active)
	target.active_effects.append(record)

func _make_effect_record(effect_id:String,definition:Dictionary,event:CombatEvent)->Dictionary:
	var stack_id := "%s:%d" % [effect_id, _next_effect_stack_id]
	_next_effect_stack_id += 1
	return {"effect_id":effect_id,"definition":definition.duplicate(true),"source_id":event.source_id,"source_type":String(event.payload.get("source_type","unknown")),"source_instance_id":String(event.payload.get("source_instance_id","")),"stack_id":stack_id,"start_round":state.round_number + 1,"remaining_rounds":int(definition.get("duration_rounds",1))}

func _effect_flag(target: CombatantState, field: String) -> bool:
	return CombatModifierService.flag(target, field, state.round_number)

func _active_effect_value(target: CombatantState, field: String) -> float:
	return CombatModifierService.modifier(target, field, state.round_number)

func _effect_definition(effect_id: String) -> Dictionary:
	return physical_balance.get("effects", {}).get(effect_id, {})

func _queue_counterattack(parent: CombatEvent, defender: CombatantState, attacker: CombatantState, rolls: Dictionary) -> void:
	if bool(parent.payload.get("is_counterattack", false)): return
	var chance := CombatModifierService.combat_chance(defender, "counterattack_rating", "counterattack", state.round_number)
	if not CombatMath.roll_success(chance, int(rolls.get("counterattack", 100))): return
	var weapon:=_counterattack_weapon_profile(defender)
	if weapon.is_empty(): return
	var counter_rolls:Dictionary=Dictionary(parent.payload.get("counterattack_rolls",{})).duplicate(true)
	var damage_roll:=float(counter_rolls.get("damage",randf()))
	counter_rolls["damage"]=damage_roll
	var damage_min:=float(weapon.get("damage_min",defender.combat_stats.get("main_hand_damage",0.0)))
	var damage_max:=float(weapon.get("damage_max",damage_min))
	var raw_damage:=CombatMath.roll_damage(damage_min,damage_max,damage_roll)*float(physical_balance.get("counterattack_damage_coefficient",0.8))
	var child := state.create_event(CombatEvent.Kind.ATTACK, defender.combatant_id, attacker.combatant_id, {
		"raw_damage":raw_damage,
		"damage_min":damage_min,
		"damage_max":damage_max,
		"damage_roll":damage_roll,
		"zone":String(parent.payload.get("counterattack_zone","chest")),
		"damage_type":String(weapon.get("damage_type",defender.combat_stats.get("main_hand_damage_type","slashing"))),
		"rolls":counter_rolls,
		"is_counterattack":true,
		"is_weapon_attack":true,
		"generates_ap":false,
		"weapon_index":int(weapon.get("weapon_index",0)),
		"attack_profile_id":String(weapon.get("id","basic")),
		"delivery_type":String(weapon.get("delivery_type","MELEE")),
		"min_zone_distance":int(weapon.get("min_zone_distance",0)),
		"max_zone_distance":int(weapon.get("max_zone_distance",0)),
		"uses_magic_hit":bool(weapon.get("uses_magic_hit",false)),
		"magic_hit_modifier":float(weapon.get("magic_hit_modifier",0.0)),
		"magic_hit_roll":int(counter_rolls.get("magic_hit",1)),
		"uses_physical_block":not bool(weapon.get("uses_magic_hit",false)),
		"bypass_physical_mitigation":not String(weapon.get("damage_type","slashing")).to_lower() in ["physical","slashing","piercing","chopping","blunt"]
	}, parent.event_id)
	state.queue_event(child); parent.set_result("counterattack_event_id", child.event_id)

func _counterattack_weapon_profile(combatant:CombatantState)->Dictionary:
	var by_weapon:Dictionary={}
	for profile in WeaponAttackProfile.all(combatant):
		if int(profile.get("min_zone_distance",0))>0 or int(profile.get("max_zone_distance",0))<0:
			continue
		var weapon_index:=int(profile.get("weapon_index",-1))
		if not by_weapon.has(weapon_index):
			by_weapon[weapon_index]=[]
		by_weapon[weapon_index].append(profile)
	var weapon_indices:Array=by_weapon.keys()
	weapon_indices.sort()
	for raw_weapon_index in weapon_indices:
		var profiles:Array=by_weapon[raw_weapon_index]
		if profiles.size()==1:
			return Dictionary(profiles[0]).duplicate(true)
		var selected:Dictionary={}
		for raw_profile in profiles:
			var candidate:Dictionary=raw_profile
			if bool(candidate.get("is_default",false)):
				if not selected.is_empty():
					selected={}
					break
				selected=candidate
		if not selected.is_empty():
			return selected.duplicate(true)
	return {}
func _gain_basic_attack_ap(attacker: CombatantState, event: CombatEvent) -> void:
	if not bool(event.payload.get("generates_ap",true)) or bool(event.payload.get("is_counterattack",false)) or bool(event.payload.get("is_extra_attack",false)):
		return
	# A Base Attack earns AP only when one of its constituent attacks connects.
	if String(event.result.get("outcome",""))!="connected":
		return
	var ap_group_id:=int(event.payload.get("ap_group_id",event.event_id))
	for logged_event in state.event_log:
		if int(logged_event.payload.get("ap_group_id",logged_event.event_id))==ap_group_id and int(logged_event.result.get("ap_gained",0))>0:
			return
	event.set_result("ap_gained",attacker.gain_action_points(int(physical_balance.get("basic_physical_attack_ap_gain",1))))

func _weapon_skill_hit_penalty(attacker: CombatantState, weapon_index: int) -> float:
	var profiles:Array=attacker.combat_stats.get("weapon_profiles",[])
	if profiles.is_empty(): return 0.0
	var profile:Dictionary=profiles[clampi(weapon_index,0,profiles.size()-1)]
	var weapon_class:=String(profile.get("weapon_class",""))
	if weapon_class.is_empty(): return 0.0
	var item_level:=maxi(1,int(profile.get("item_level",1)))
	var deficit:=maxi(0,item_level-attacker.weapon_skill(weapon_class))
	return float(mini(deficit,80))

func _hit_chance(level_difference: int) -> float:
	var table: Dictionary = physical_balance.get("hit_by_level_difference", {})
	if table.is_empty(): return 95.0
	return float(table.get(str(clampi(level_difference, -10, 5)), 95.0))
func _active_defence_available(tempo: float, roll: int) -> bool:
	if tempo <= -100.0: return false
	if tempo >= 0.0: return true
	return CombatMath.roll_success(100.0 + tempo, roll)
func _event_uses_physical_block(event: CombatEvent) -> bool:
	if not event.payload.has("uses_physical_block"):
		return true
	return bool(event.payload.get("uses_physical_block", false))

func _manual_block_success(event: CombatEvent, defender: CombatantState) -> bool:
	if not defender.can_manual_block():
		return false
	var attack_zone:=String(event.payload.get("zone",""))
	var chosen_zones:Array=defender.combat_stats.get("manual_block_zones",[])
	if chosen_zones.is_empty():
		var legacy_zone:=String(defender.combat_stats.get("manual_block_zone",""))
		if not legacy_zone.is_empty():
			chosen_zones=[legacy_zone]
	return chosen_zones.has(attack_zone)
func _block_crushed(attacker: CombatantState, rolls: Dictionary) -> bool:
	return CombatMath.roll_success(float(attacker.combat_stats.get("block_crush", 0.0)), int(rolls.get("block_crush", 100)))
func _armour_for(defender: CombatantState, zone: String, damage_type: String) -> float:
	var zone_armour: Dictionary = defender.armour.get(zone, {}); return float(zone_armour.get(damage_type, 0.0))


func _is_magic_damage_type(damage_type:String) -> bool:
	return ["fire","water","frost","air","earth","dark","light","lightning"].has(damage_type.to_lower())

func _magic_resist(target:CombatantState, resist_type:String) -> float:
	if resist_type.is_empty():
		return 0.0
	var raw := float(target.magic_resists.get(resist_type.to_lower(), 0.0))
	if raw > 1.0:
		raw /= 100.0
	return clampf(raw, 0.0, 1.0)


func _physical_ranged_distance_hit_modifier(event:CombatEvent)->float:
	if zone_state==null or String(event.payload.get("delivery_type",""))!="PROJECTILE":
		return 0.0
	if bool(event.payload.get("uses_magic_hit",false)):
		return 0.0
	return _distance_modifier(event,event.target_id)

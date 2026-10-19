class_name CombatEngine
extends RefCounted

var state: CombatState
var combat_rng := RandomNumberGenerator.new()

func attack_rolls() -> Dictionary:
	return {"hit": combat_rng.randi_range(1,100), "magic_hit": combat_rng.randi_range(1,100), "reaction": combat_rng.randi_range(1,100), "dodge": combat_rng.randi_range(1,100), "auto_block": combat_rng.randi_range(1,100), "block_crush": combat_rng.randi_range(1,100), "crit": combat_rng.randi_range(1,100), "counterattack": combat_rng.randi_range(1,100), "on_hit_effect": combat_rng.randi_range(1,100), "manual_block_effect": combat_rng.randi_range(1,100), "damage": combat_rng.randf()}

func complete_attack_rolls(provided: Dictionary) -> Dictionary:
	var result := provided.duplicate(true)
	for key in ["hit", "magic_hit", "reaction", "dodge", "auto_block", "block_crush", "crit", "counterattack", "on_hit_effect", "manual_block_effect"]:
		if not result.has(key):
			result[key] = combat_rng.randi_range(1, 100)
	if not result.has("damage"):
		result["damage"] = combat_rng.randf()
	var counter: Dictionary = Dictionary(result.get("counterattack_rolls", {})).duplicate(true)
	for key in ["hit", "magic_hit", "reaction", "dodge", "auto_block", "block_crush", "crit", "counterattack", "on_hit_effect", "manual_block_effect"]:
		if not counter.has(key):
			counter[key] = combat_rng.randi_range(1, 100)
	if not counter.has("damage"):
		counter["damage"] = combat_rng.randf()
	result["counterattack_rolls"] = counter
	return result

var physical_balance: Dictionary
var canonical_effects: Dictionary = {}
var _balance_valid := true
var _next_effect_stack_id: int = 1
var group_state:GroupCombatState
var zone_state:CombatZoneState

const HIT_ZONES:=["head","chest","arms","waist","legs"]

func configure_spatial_context(groups:GroupCombatState,zones:CombatZoneState)->void:
	group_state=groups
	zone_state=zones

func _init(combat_state: CombatState, balance: Dictionary = {}) -> void:
	state = combat_state
	canonical_effects = EffectCatalog.load_json()
	physical_balance = balance.duplicate(true)
	if balance.is_empty():
		var file := FileAccess.open("res://data/balance/physical_combat.json", FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		if not parsed is Dictionary or not parsed.get("hit_by_level_difference") is Dictionary or not parsed.get("armour_reduction_curve") is Array or parsed.get("armour_reduction_curve", []).is_empty():
			_balance_valid = false
			push_error("CombatEngine: required physical_combat.json is missing or invalid")
			return
		physical_balance = parsed

func resolve_pending_events() -> void:
	while not state.pending_events.is_empty():
		var event: CombatEvent = state.pending_events.pop_front()
		resolve_event(event)

func resolve_event(event: CombatEvent) -> void:
	if not _balance_valid:
		event.set_result("outcome", "invalid_balance_config")
		state.record_event(event)
		return
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
	if source.is_death_finalized():
		event.set_result("outcome", "source_dead")
		return
	if not _require_canonical(event, source):
		return
	if CombatTempoService.is_stunned(source, state.round_number):
		event.set_result("outcome", "stunned")
		return
	var target_ids := _valid_action_targets(event)
	if target_ids.is_empty():
		event.set_result("outcome", "invalid_combatant")
		return
	for target_id in target_ids:
		if not _require_canonical(event, state.get_combatant(String(target_id))):
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
		if not ["damage","effect","heal","cleanse"].has(kind):
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
		elif kind=="effect" and String(event.payload.get("target_team",""))=="ALLY":
			has_support=true
		elif kind=="cleanse":
			if String(event.payload.get("target_team","")).to_upper()=="ALLY":
				has_support=true
			else:
				has_offense=true
		elif kind in ["damage","effect"]:
			has_offense=true
	return String(event.payload.get("target_team",""))=="ALLY" or (has_support and not has_offense)

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
	var target := state.get_combatant(target_id)
	if not _require_canonical(event, source) or not _require_canonical(event, target):
		return false
	var chance := _common_hit_chance(source, target) + float(event.payload.get("magic_hit_modifier",0.0)) + _distance_modifier(event,target_id)
	# Roll once per cast using the seeded engine RNG, then reuse the result
	# for every component of the same ability. Explicit rolls remain testable.
	var magic_roll := int(event.payload.get("magic_hit_roll", 0))
	if magic_roll < 1 or magic_roll > 100:
		magic_roll = combat_rng.randi_range(1,100)
		event.payload["magic_hit_roll"] = magic_roll
	event.set_result("magic_hit_roll", magic_roll)
	return CombatMath.roll_success(clampf(chance,0.0,100.0), magic_roll)

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
		if CombatDamagePayload.is_magic_damage_type(damage_type):
			var caster := state.get_combatant(parent.source_id)
			if caster != null:
				var bonus_percent := CombatModifierService.effective_percent(caster, "magic_damage_rating", state.round_number)
				# Magic damage rating and direct percentage bonuses use one overlay.
				amount = maxf(0.0, amount) * maxf(0.0, 1.0 + bonus_percent / 100.0)
		amount *= scale
		if delivery_type in ["MELEE", "PROJECTILE"]:
			return state.create_event(CombatEvent.Kind.ATTACK, parent.source_id, target_id, CombatDamagePayload.ability_attack_payload(parent, component, amount, scale), parent.event_id)
		var direct_payload := CombatDamagePayload.direct_damage_payload(parent, damage_type, amount, "ability")
		direct_payload["aoe_scale"] = scale
		return state.create_event(CombatEvent.Kind.DAMAGE, parent.source_id, target_id, direct_payload, parent.event_id)
	if kind == "cleanse":
		return state.create_event(CombatEvent.Kind.EFFECT,parent.source_id,target_id,{
			"dispel_polarity":String(component.get("dispel_polarity","")).to_upper(),
			"max_effects":maxi(1,int(component.get("max_effects",1))),
			"source_type":"ability",
			"ability_id":String(parent.payload.get("ability_id","")),
			"delivery_type":delivery_type
		},parent.event_id)
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
			"aoe_scale": scale,
			"preparation_effect": String(parent.payload.get("resolution_phase", "COMBAT")) == "PREPARATION"
		}, parent.event_id)
	return null

func _resolve_attack(event: CombatEvent) -> void:
	var attacker := state.get_combatant(event.source_id)
	var defender := state.get_combatant(event.target_id)
	if attacker == null or defender == null:
		event.set_result("outcome", "invalid_combatant"); return
	if attacker.is_death_finalized() or defender.is_death_finalized():
		event.set_result("outcome", "source_dead" if attacker.is_death_finalized() else "target_dead")
		return
	if not _require_canonical(event, attacker) or not _require_canonical(event, defender):
		return
	if CombatTempoService.is_stunned(attacker, state.round_number):
		event.set_result("outcome", "stunned")
		return
	var rolls: Dictionary = event.payload.get("rolls", {})
	var uses_magic_hit:=bool(event.payload.get("uses_magic_hit",false))
	var distance_hit_modifier:=_distance_modifier(event,event.target_id) if uses_magic_hit else _physical_ranged_distance_hit_modifier(event)
	var is_weapon_attack:=bool(event.payload.get("is_weapon_attack",event.payload.has("weapon_index") and String(event.payload.get("source_kind",""))!="ability"))
	var weapon_skill_penalty:=0.0 if uses_magic_hit or not is_weapon_attack else _weapon_skill_hit_penalty(attacker, int(event.payload.get("weapon_index",0)))
	var shared_hit := _common_hit_chance(attacker, defender)
	var hit_chance := shared_hit - weapon_skill_penalty + distance_hit_modifier
	if uses_magic_hit:
		hit_chance += float(event.payload.get("magic_hit_modifier",0.0))
	event.set_result("distance_hit_modifier",distance_hit_modifier)
	event.set_result("weapon_skill_hit_penalty",weapon_skill_penalty)
	event.set_result("hit_system","magic" if uses_magic_hit else "physical")
	var hit_roll:=int(event.payload.get("magic_hit_roll",rolls.get("magic_hit",1))) if uses_magic_hit else int(rolls.get("hit",100))
	event.set_result("hit_chance",clampf(hit_chance,0.0,100.0))
	event.set_result("hit_roll",hit_roll)
	if not bool(event.payload.get("hit_already_resolved", false)) and not CombatMath.roll_success(clampf(hit_chance,0.0,100.0),hit_roll):
		event.set_result("outcome", "magic_miss" if uses_magic_hit else "miss"); _gain_basic_attack_ap(attacker, event); return
	var active_defence_available := not uses_magic_hit and not CombatTempoService.is_stunned(defender, state.round_number) and not _effect_flag(defender, "active_defence_locked")
	event.set_result("active_defence_available",active_defence_available)
	if active_defence_available:
		var dodge := CombatMath.effective_dodge(CombatModifierService.effective_percent(defender, "dodge_rating", state.round_number), CombatModifierService.effective_percent(attacker, "anti_dodge_rating", state.round_number))
		event.set_result("dodge_chance",dodge)
		event.set_result("dodge_roll",int(rolls.get("dodge", 100)))
		if CombatMath.roll_success(dodge, int(rolls.get("dodge", 100))):
			event.set_result("outcome", "dodge"); _queue_counterattack(event, defender, attacker, rolls); _gain_basic_attack_ap(attacker, event); return
		event.set_result("uses_physical_block",_event_uses_physical_block(event))
		if _event_uses_physical_block(event) and _manual_block_success(event, defender):
			event.set_result("block_crush_chance",CombatModifierService.block_crush_chance(attacker, state.round_number))
			event.set_result("block_crush_roll",int(rolls.get("block_crush", 100)))
			var manual_block_crushed:=_block_crushed(attacker, rolls)
			event.set_result("manual_block_crushed",manual_block_crushed)
			if not manual_block_crushed:
				event.set_result("outcome", "manual_block")
				_trigger_manual_block_effects(event, defender, rolls)
				_gain_basic_attack_ap(attacker, event); return
		var auto_block := CombatModifierService.block_chance(defender, state.round_number)
		event.set_result("auto_block_chance",auto_block)
		event.set_result("auto_block_roll",int(rolls.get("auto_block", 100)))
		if _event_uses_physical_block(event) and defender.can_auto_block() and CombatMath.roll_success(auto_block, int(rolls.get("auto_block", 100))):
			event.set_result("block_crush_chance",CombatModifierService.block_crush_chance(attacker, state.round_number))
			event.set_result("block_crush_roll",int(rolls.get("block_crush", 100)))
			var auto_block_crushed:=_block_crushed(attacker, rolls)
			event.set_result("auto_block_crushed",auto_block_crushed)
			if not auto_block_crushed:
				event.set_result("outcome", "auto_block"); _gain_basic_attack_ap(attacker, event); return

	var active_crit_bonus := _active_effect_value(attacker, "crit_bonus")
	var crit := CombatMath.effective_crit(CombatModifierService.effective_percent(attacker, "crit_chance_rating", state.round_number) + active_crit_bonus, CombatModifierService.effective_percent(defender, "anti_crit_rating", state.round_number))
	var is_crit := CombatMath.roll_success(crit, int(rolls.get("crit", 100)))
	var raw_damage := float(event.payload.get("raw_damage", 0.0))
	# PAR053–056: physical damage bonus applies only to the matching damage type.
	# Percent values are stored as percentages (e.g. 30 means +30%).
	var physical_type := String(event.payload.get("damage_type", "")).to_lower()
	if physical_type in ["piercing", "slashing", "chopping", "blunt"]:
		var physical_bonus := CombatModifierService.effective_stat(attacker, "physical_damage_" + physical_type + "_pct", state.round_number)
		raw_damage *= maxf(0.0, 1.0 + physical_bonus / 100.0)
	if CombatDamagePayload.is_magic_damage_type(String(event.payload.get("damage_type", ""))) and not bool(event.payload.get("magic_rating_applied", false)):
		raw_damage *= maxf(0.0, 1.0 + CombatModifierService.effective_percent(attacker, "magic_damage_rating", state.round_number) / 100.0)
	if is_crit:
		var critical_rating_bonus := CombatModifierService.effective_percent(attacker, "crit_damage_rating", state.round_number)
		raw_damage *= float(physical_balance.get("crit_damage_multiplier", 1.5)) + critical_rating_bonus / 100.0
	if _event_bypasses_physical_mitigation(event):
		var ability_damage := state.create_event(CombatEvent.Kind.DAMAGE, event.source_id, event.target_id, CombatDamagePayload.direct_damage_payload(event, String(event.payload.get("damage_type", "physical")), raw_damage, "ability"), event.event_id)
		state.queue_event(ability_damage)
		event.set_result("outcome", "connected")
		event.set_result("critical", is_crit)
		event.set_result("crit_chance", crit)
		event.set_result("raw_damage", raw_damage)
		event.set_result("damage_event_id", ability_damage.event_id)
		# Non-physical weapon attacks still complete the weapon pipeline.
		if is_weapon_attack:
			_trigger_weapon_on_hit(event, attacker, defender, rolls)
		_gain_basic_attack_ap(attacker, event)
		return

	var zone := String(event.payload.get("zone", "chest")); var damage_type := String(event.payload.get("damage_type", "slashing"))
	# PAR127–130 are global flat armour: identical bonus in all five zones.
	var base_armour:=_armour_for(defender, zone, damage_type) + CombatModifierService.global_physical_armour(defender, damage_type, state.round_number)
	var armour_penetration_flat:=CombatModifierService.armour_penetration_flat(attacker, state.round_number)
	var armour_penetration_percent:=CombatModifierService.armour_reduction_percent(attacker, state.round_number)
	var typed_armour_penetration_percent:=CombatModifierService.typed_armour_penetration_percent(attacker, damage_type, state.round_number)
	# PAR126 and PAR131–134 reduce the matching armour sequentially.
	var effective_armour := maxf(0.0, base_armour * (1.0 - armour_penetration_percent) * (1.0 - typed_armour_penetration_percent))
	var armour_percent := RatingMatrix.to_percent(effective_armour * 10.0, defender.level)
	var penetration_percent := RatingMatrix.to_percent(maxf(0.0, armour_penetration_flat) * 10.0, attacker.level)
	var reduction := clampf((armour_percent - penetration_percent) / 100.0, 0.0, 1.0)
	var after_armour := raw_damage * (1.0 - clampf(reduction, 0.0, 1.0))
	var damage_event := state.create_event(CombatEvent.Kind.DAMAGE, event.source_id, event.target_id, {"amount": after_armour, "damage_type": damage_type, "zone": zone, "source": "attack"}, event.event_id)
	state.queue_event(damage_event)
	event.set_result("outcome", "connected"); event.set_result("critical", is_crit); event.set_result("crit_chance",crit); event.set_result("crit_roll",int(rolls.get("crit", 100))); event.set_result("raw_damage", raw_damage); event.set_result("base_armour",base_armour); event.set_result("armour_penetration_flat",armour_penetration_flat); event.set_result("armour_penetration_percent",armour_penetration_percent); event.set_result("typed_armour_penetration_percent",typed_armour_penetration_percent); event.set_result("effective_armour",effective_armour); event.set_result("armour_reduction",reduction); event.set_result("after_armour_damage",after_armour); event.set_result("damage_event_id", damage_event.event_id)
	if is_weapon_attack:
		_trigger_weapon_on_hit(event, attacker, defender, rolls)
	_gain_basic_attack_ap(attacker, event)

func _resolve_damage(event: CombatEvent) -> void:
	var target := state.get_combatant(event.target_id)
	if target == null: event.set_result("error", "target_not_found"); return
	# Negative provisional HP is allowed until end_round; finalized death is not.
	if target.is_death_finalized():
		event.set_result("outcome", "target_dead")
		event.set_result("connected", false)
		event.set_result("final_damage", 0)
		event.set_result("hp_removed", 0)
		return
	var amount := float(event.payload.get("amount", 0.0))
	var damage_type := String(event.payload.get("damage_type", ""))
	var magic_resist := CombatModifierService.magic_resist(target, damage_type, state.round_number)
	if CombatDamagePayload.is_magic_damage_type(damage_type):
		amount *= 1.0 - magic_resist
		event.set_result("magic_resist", magic_resist)
	var total_reduction := CombatModifierService.damage_reduction(target, state.round_number)
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
	if target==null or target.is_death_finalized():
		event.set_result("resolved",false)
		if target!=null:
			event.set_result("outcome", "target_dead")
		return
	if event.payload.has("dispel_polarity"):
		_resolve_dispel(event,target)
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
	var resist := 0.0 if effect_kind == "hot" else CombatModifierService.magic_resist(target, resist_type, state.round_number)
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
		# Tempo control is a one-time accumulated hit, never a repeat overlay.
		var tempo_delta := float(definition.get("tempo_modifier", 0.0)) + float(definition.get("tempo", 0.0))
		# Legacy stun/freeze/fear without an explicit magnitude is equivalent
		# to a -100 control hit; actual stun still starts on the next round.
		if not definition.has("tempo_modifier") and not definition.has("tempo") and kind in ["stun", "freeze", "fear"]:
			tempo_delta = -100.0
		if tempo_delta < 0.0:
			CombatTempoService.apply_control(target, -tempo_delta)
		elif tempo_delta > 0.0:
			target.tempo = minf(target.max_tempo, target.tempo + tempo_delta)
		_apply_timed_effect(target, effect_id, definition, event)
	event.set_result("effect_id", effect_id); event.set_result("resolved", true)

## Remove matching beneficial/harmful EFF records, including all their stacks.
## Unknown polarity cannot be dispelled accidentally; content may declare it.
func _resolve_dispel(event:CombatEvent,target:CombatantState) -> void:
	var polarity:=String(event.payload.get("dispel_polarity","")).to_upper()
	if not ["BUFF","DEBUFF"].has(polarity):
		event.set_result("resolved",false)
		event.set_result("outcome","invalid_dispel_polarity")
		return
	var limit:=maxi(1,int(event.payload.get("max_effects",1)))
	var removed:Array[String]=[]
	for active in target.active_effects.duplicate():
		if removed.size()>=limit:
			break
		var definition:Dictionary=Dictionary(active.get("definition",{}))
		var category:=String(definition.get("dispel_polarity","")).to_upper()
		if category.is_empty():
			match String(definition.get("kind","")).to_lower():
				"hot","buff","shield": category="BUFF"
				"dot","debuff","stun","freeze","fear": category="DEBUFF"
		if category!=polarity:
			continue
		removed.append(String(active.get("effect_id","")))
		target.active_effects.erase(active)
	event.set_result("resolved",not removed.is_empty())
	event.set_result("removed_effect_ids",removed)
	event.set_result("removed_count",removed.size())

func _trigger_weapon_on_hit(parent: CombatEvent, attacker: CombatantState, defender: CombatantState, rolls: Dictionary) -> void:
	var effects:Array=CombatModifierService.weapon_on_hit_effects(attacker)
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
	var triggers: Array = CombatModifierService.manual_block_effects(defender)
	for trigger in triggers:
		if CombatMath.roll_success(float(trigger.get("chance", 0.0)), int(rolls.get("manual_block_effect", 100))):
			var payload := {"effect_id":String(trigger.get("effect_id", "")),"source_type":String(trigger.get("source_type", "item")),"source_instance_id":String(trigger.get("source_instance_id", ""))}
			state.queue_event(state.create_event(CombatEvent.Kind.EFFECT, defender.combatant_id, defender.combatant_id, payload, parent.event_id))

func _apply_timed_effect(target: CombatantState, effect_id: String, definition: Dictionary, event: CombatEvent) -> void:
	var stacking := String(definition.get("stacking", "unique"))
	var max_stacks := maxi(1, int(definition.get("max_stacks", 1)))
	var matching:Array = []
	for active in target.active_effects:
		if String(active.get("effect_id", "")) == effect_id and (stacking != "shared_duration" or String(active.get("source_id", "")) == event.source_id): matching.append(active)
	# Shared-duration DoT is per effect and caster. New stacks join the tick
	# starting NEXT round; only previously active stacks deal damage this round.
	# Refresh counts three future ticks, including when already at stack cap.
	if stacking == "shared_duration":
		if matching.is_empty():
			var shared_record := _make_effect_record(effect_id, definition, event)
			shared_record["stacks"] = 1
			shared_record["active_stacks"] = 0
			target.active_effects.append(shared_record)
		else:
			var shared: Dictionary = matching[0]
			shared["stacks"] = mini(max_stacks, maxi(1, int(shared.get("stacks", 1))) + 1)
			# End-of-round expiry decrements records already active this round.
			var ticks := maxi(1, int(definition.get("duration_rounds", 1)))
			shared["remaining_rounds"] = ticks + (1 if state.round_number >= int(shared.get("start_round", 999999)) else 0)
		return
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
	var starts_now := bool(event.payload.get("preparation_effect",false))
	return {"effect_id":effect_id,"definition":definition.duplicate(true),"source_id":event.source_id,"source_type":String(event.payload.get("source_type","unknown")),"source_instance_id":String(event.payload.get("source_instance_id","")),"stack_id":stack_id,"start_round":state.round_number if starts_now else state.round_number + 1,"remaining_rounds":int(definition.get("duration_rounds",1))}

func _effect_flag(target: CombatantState, field: String) -> bool:
	return CombatModifierService.flag(target, field, state.round_number)

func _active_effect_value(target: CombatantState, field: String) -> float:
	return CombatModifierService.modifier(target, field, state.round_number)

func _effect_definition(effect_id: String) -> Dictionary:
	# Explicit combat-fixture definitions override canonical content only in
	# their injected test balance; ordinary combat uses the EFF catalog.
	var override: Variant = Dictionary(physical_balance.get("effects", {})).get(effect_id, null)
	if override is Dictionary:
		return override
	return EffectCatalog.definition(canonical_effects, effect_id)

func _queue_counterattack(parent: CombatEvent, defender: CombatantState, attacker: CombatantState, rolls: Dictionary) -> void:
	if bool(parent.payload.get("is_counterattack", false)): return
	var chance := CombatModifierService.effective_percent(defender, "counterattack_rating", state.round_number)
	if not CombatMath.roll_success(chance, int(rolls.get("counterattack", 100))): return
	var weapon:=_counterattack_weapon_profile(defender)
	if weapon.is_empty(): return
	var counter_rolls:Dictionary=Dictionary(rolls.get("counterattack_rolls", parent.payload.get("counterattack_rolls",{}))).duplicate(true)
	var damage_roll:=float(counter_rolls["damage"]) if counter_rolls.has("damage") else combat_rng.randf()
	counter_rolls["damage"]=damage_roll
	var payload:=WeaponAttackProfile.attack_payload(weapon,counter_rolls,String(parent.payload.get("counterattack_zone","chest")),{
		"damage_multiplier":float(physical_balance.get("counterattack_damage_coefficient",0.8)),
		"is_counterattack":true,
		"generates_ap":false,
	})
	var child := state.create_event(CombatEvent.Kind.ATTACK, defender.combatant_id, attacker.combatant_id, payload, parent.event_id)
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
	var profile:Dictionary={}
	for candidate in WeaponAttackProfile.all(attacker):
		if int(candidate.get("weapon_index",-1))==weapon_index:
			profile=candidate
			break
	if profile.is_empty(): return 0.0
	var weapon_class:=String(profile.get("weapon_class",""))
	if weapon_class.is_empty(): return 0.0
	var item_level:=maxi(1,int(profile.get("item_level",1)))
	var deficit:=maxi(0,item_level-attacker.weapon_skill(weapon_class))
	return float(mini(deficit,80))

func _hit_chance(level_difference: int) -> float:
	var table: Dictionary = physical_balance.get("hit_by_level_difference", {})
	if table.is_empty(): return 95.0
	return float(table.get(str(clampi(level_difference, -10, 5)), 95.0))
func _event_uses_physical_block(event: CombatEvent) -> bool:
	if not event.payload.has("uses_physical_block"):
		return bool(CombatDamagePayload.defence_flags(String(event.payload.get("damage_type","physical"))).get("uses_physical_block",true))
	return bool(event.payload.get("uses_physical_block", false))

func _event_bypasses_physical_mitigation(event: CombatEvent) -> bool:
	if not event.payload.has("bypass_physical_mitigation"):
		return bool(CombatDamagePayload.defence_flags(String(event.payload.get("damage_type","physical"))).get("bypass_physical_mitigation",false))
	return bool(event.payload.get("bypass_physical_mitigation", false))

func _manual_block_success(event: CombatEvent, defender: CombatantState) -> bool:
	if not defender.can_manual_block():
		return false
	var attack_zone:=String(event.payload.get("zone",""))
	var chosen_zones:Array=CombatModifierService.manual_block_zones(defender)
	return chosen_zones.has(attack_zone)
func _block_crushed(attacker: CombatantState, rolls: Dictionary) -> bool:
	var chance:=CombatModifierService.block_crush_chance(attacker, state.round_number)
	return CombatMath.roll_success(chance, int(rolls.get("block_crush", 100)))
func _armour_for(defender: CombatantState, zone: String, damage_type: String) -> float:
	var zone_armour: Dictionary = defender.armour.get(zone, {}); return float(zone_armour.get(damage_type, 0.0))


func _magic_resist(target:CombatantState, resist_type:String) -> float:
	return CombatModifierService.magic_resist(target, resist_type, state.round_number)


func _physical_ranged_distance_hit_modifier(event:CombatEvent)->float:
	if zone_state==null or String(event.payload.get("delivery_type",""))!="PROJECTILE":
		return 0.0
	if bool(event.payload.get("uses_magic_hit",false)):
		return 0.0
	return _distance_modifier(event,event.target_id)

func _require_canonical(event: CombatEvent, combatant: CombatantState) -> bool:
	var checked := ParCombatContract.validate(combatant)
	if not bool(checked.ok):
		push_error("Combat PAR invariant violated: " + String(checked.reason))
		event.set_result("outcome", "invalid_par_contract")
		event.set_result("error", checked.reason)
		return false
	for key in ParCombatContract.RATINGS.values():
		if not is_finite(CombatModifierService.effective_percent(combatant, key, state.round_number)):
			event.set_result("outcome", "invalid_par_contract")
			event.set_result("error", "invalid_runtime_" + String(key))
			return false
	return true

func _common_hit_chance(source: CombatantState, target: CombatantState) -> float:
	return _hit_chance(source.level - target.level) + CombatModifierService.effective_percent(source, "hit_chance_rating", state.round_number)

extends SceneTree

## Numeric physical PAR gate: real item -> canonical snapshot -> combat engine.
## Every test is deterministic, with fixed hit/defence/critical rolls.
var errors: Array[String] = []
var next_id := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)

func _initialize() -> void:
	matrix_cases()
	damage_cases()
	penetration_cases()
	npc_cases()
	for message in errors:
		push_error(message)
	print("PHYSICAL_PAR_BOUNDARY_TEST=", "PASS" if errors.is_empty() else "FAIL", " failures=", errors.size())
	quit(0 if errors.is_empty() else 1)

func fighter(par_stats: Dictionary = {}, structural_armour: Dictionary = {}, base_armour: Dictionary = {}) -> CombatantState:
	next_id += 1
	var character := CharacterState.new("physical_par_%d" % next_id, "Physical PAR", 1)
	var repository := ItemRepository.new()
	if not par_stats.is_empty() or not structural_armour.is_empty():
		var id := "physical_par_ring_%d" % next_id
		var item := {
			"instance_id": id,
			"equip_slots": ["ring1"],
			"slot_usage": ["ring1"],
			"par_stats": par_stats.duplicate(true),
			"armour_by_zone": structural_armour.duplicate(true)
		}
		ItemDurabilityService.initialize_item(item, 100)
		if not (repository.add_item(item) and character.receive_item(id, repository) and character.equip("ring1", id, repository)):
			check(false, "fixture ring could not be equipped: " + id)
			return null
	var combatant := CharacterCombatBuilder.build(character, repository, {"health":100000, "armour":base_armour})
	check(combatant != null, "fixture combatant build")
	return combatant

func strike(attacker: CombatantState, defender: CombatantState, damage_type: String, zone: String, amount: float = 100.0) -> CombatEvent:
	var state := CombatState.new()
	state.add_combatant(attacker)
	state.add_combatant(defender)
	state.begin_round()
	var event := state.create_event(CombatEvent.Kind.ATTACK, attacker.combatant_id, defender.combatant_id, {
		"raw_damage":amount,
		"damage_type":damage_type,
		"zone":zone,
		"rolls":{"hit":1,"reaction":100,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	})
	state.queue_event(event)
	CombatEngine.new(state).resolve_pending_events()
	check(event.result.get("outcome", "") == "connected", "expected connected: " + zone + "." + damage_type)
	return event

func matrix_cases() -> void:
	var empty := fighter()
	if empty == null:
		return
	for zone in EquipmentBuilder.HIT_ZONES:
		for damage_type in EquipmentBuilder.PHYSICAL_TYPES:
			check(empty.armour.has(zone) and Dictionary(empty.armour.get(zone, {})).has(damage_type), "missing zero armour: " + zone + "." + damage_type)
			check(is_equal_approx(float(Dictionary(empty.armour.get(zone, {})).get(damage_type, -1.0)), 0.0), "zero armour value: " + zone + "." + damage_type)
	var stats := {}
	var global_values := [3.0, 5.0, 7.0, 9.0]
	for zone_index in range(5):
		stats["PAR%03d" % (100 + zone_index)] = 2.0
		for type_index in range(4):
			stats["PAR%03d" % (105 + zone_index * 4 + type_index)] = 10.0 + zone_index * 4 + type_index
	for type_index in range(4):
		stats["PAR%03d" % (127 + type_index)] = global_values[type_index]
	var full := fighter(stats)
	if full == null:
		return
	for zone_index in range(5):
		var zone: String = EquipmentBuilder.HIT_ZONES[zone_index]
		for type_index in range(4):
			var damage_type: String = EquipmentBuilder.PHYSICAL_TYPES[type_index]
			var expected := 2.0 + 10.0 + zone_index * 4 + type_index + global_values[type_index]
			check(is_equal_approx(float(full.armour[zone][damage_type]), expected), "general + zoned + global exactly once: " + zone + "." + damage_type)
	var structural := fighter({}, {"chest":30.0})
	if structural != null:
		check(is_equal_approx(float(structural.armour.chest.slashing), 30.0), "legacy structural armour exactly once")

func damage_cases() -> void:
	var attacker := fighter({"PAR053":10.0, "PAR054":20.0, "PAR055":30.0, "PAR056":40.0})
	var defender := fighter()
	if attacker == null or defender == null:
		return
	for type_index in range(4):
		var damage_type: String = EquipmentBuilder.PHYSICAL_TYPES[type_index]
		var event := strike(attacker, defender, damage_type, "head")
		check(is_equal_approx(float(event.result.get("raw_damage", -1)), 100.0 + 10.0 * (type_index + 1)), "PAR053-056 correct type: " + damage_type)
	var reduction_target := fighter({"PAR135":20.0})
	if reduction_target != null:
		var hp_before := reduction_target.hp
		strike(attacker, reduction_target, "piercing", "chest")
		check(hp_before - reduction_target.hp == 88, "PAR135 20% after typed PAR053 10%: 110 -> 88")

func penetration_cases() -> void:
	var baseline := fighter({}, {}, {"chest":{"piercing":40.0,"slashing":40.0}})
	var one_percent := fighter({"PAR126":1.0})
	var combined := fighter({"PAR126":30.0,"PAR131":20.0})
	var all_typed := fighter({"PAR131":10.0,"PAR132":20.0,"PAR133":30.0,"PAR134":40.0})
	if baseline == null or one_percent == null or combined == null or all_typed == null:
		return
	var edge := strike(one_percent, baseline, "piercing", "chest")
	check(is_equal_approx(float(edge.result.get("armour_penetration_percent", -1.0)), 0.01), "PAR126 = 1 percent, never 100 percent")
	check(is_equal_approx(float(edge.result.get("effective_armour", -1.0)), 39.6), "PAR126 1% reduces 40 to 39.6")
	var pierce := strike(combined, baseline, "piercing", "chest")
	var slash := strike(combined, baseline, "slashing", "chest")
	check(is_equal_approx(float(pierce.result.get("effective_armour", -1.0)), 22.4), "PAR126 30% and PAR131 20% sequential")
	check(is_equal_approx(float(slash.result.get("effective_armour", -1.0)), 28.0), "PAR131 never affects slashing")
	for type_index in range(4):
		var damage_type: String = EquipmentBuilder.PHYSICAL_TYPES[type_index]
		var attacker := all_typed
		var head_armour := {}
		head_armour[damage_type] = 40.0
		var target := fighter({}, {}, {"head":head_armour})
		var result := strike(attacker, target, damage_type, "head")
		check(is_equal_approx(float(result.result.get("effective_armour", -1.0)), 40.0 * (1.0 - float(type_index + 1) / 10.0)), "PAR131-134 type: " + damage_type)
	var full_pen := fighter({"PAR131":100.0})
	var full_event := strike(full_pen, baseline, "piercing", "chest")
	check(is_zero_approx(float(full_event.result.get("effective_armour", -1.0))), "typed penetration 100%")
	var flat_attacker := fighter({"PAR125":30.0})
	var flat_target := fighter({}, {}, {"chest":{"slashing":50.0}})
	if flat_attacker != null and flat_target != null:
		var before := flat_target.hp
		var event := strike(flat_attacker, flat_target, "slashing", "chest")
		check(is_equal_approx(float(event.result.get("armour_reduction", -1)), 0.2), "PAR125 rating conversion after 50% armour")
		check(before - flat_target.hp == 80, "PAR125 net damage 80")
	var overlay_target := fighter({"PAR127":30.0})
	if overlay_target != null:
		overlay_target.active_effects.append({
			"definition":{"physical_resist_piercing":5.0},
			"start_round":1,"remaining_rounds":1
		})
		var overlay_event := strike(one_percent, overlay_target, "piercing", "legs")
		check(is_equal_approx(float(overlay_event.result.get("base_armour", -1)), 35.0), "global type armour + runtime overlay once")
	var overlay_attacker := fighter({"PAR131":25.0})
	if overlay_attacker != null:
		overlay_attacker.active_effects.append({
			"definition":{"armour_pen_piercing":10.0},
			"start_round":1,"remaining_rounds":1
		})
		var overlay_attack := strike(overlay_attacker, baseline, "piercing", "chest")
		check(is_equal_approx(float(overlay_attack.result.get("effective_armour", -1.0)), 26.0), "typed penetration + runtime overlay once")

func npc_cases() -> void:
	var totals := {
		"PAR052":0.0,"PAR057":1.0,"PAR073":1.0,
		"PAR100":11.0,"PAR105":7.0,"PAR127":3.0,
		"PAR053":25.0,"PAR071":20.0,"PAR125":5.0,
		"PAR126":1.0,"PAR135":10.0
	}
	for par_id in ParCombatContract.RATINGS:
		totals[par_id] = 0.0
	var npc := NpcState.new({
		"id":"physical_par_npc","name":"NPC physical PAR","level":1,
		"base":{
			"health":1000,
			"par_totals":totals,
			"par_attack_ranges":{"PAR050":{"min":2.0,"max":4.0,"type":"piercing"}},
			"combat_stats":{"weapon_profiles":[{"slot":"main_hand","damage_min":2.0,"damage_max":4.0,"damage_type":"piercing"}]},
			"armour":{"head":{"piercing":5.0}}
		}
	})
	var enemy := NpcCombatBuilder.build(npc)
	check(enemy != null, "real NPC PAR combat builder")
	if enemy == null:
		return
	check(is_equal_approx(float(enemy.armour.head.piercing), 26.0), "NPC base 5 + general 11 + zone 7 + global 3")
	check(is_equal_approx(float(enemy.armour.chest.piercing), 3.0), "NPC global typed armour in every zone")
	check(enemy.armour.has("legs") and enemy.armour.legs.has("blunt"), "NPC complete zero 5x4 matrix")
	check(is_equal_approx(CombatModifierService.effective_stat(enemy, "physical_damage_piercing_pct", 1), 25.0), "NPC PAR053 adapter")
	check(is_equal_approx(CombatModifierService.armour_reduction_percent(enemy, 1), 0.01), "NPC PAR126 adapter")
	check(is_equal_approx(CombatModifierService.armour_penetration_flat(enemy, 1), 5.0), "NPC PAR125 adapter")
	check(is_equal_approx(CombatModifierService.damage_reduction(enemy, 1), 0.1), "NPC PAR135 adapter")
	check(is_equal_approx(CombatModifierService.block_chance(enemy, 1), 20.0), "NPC PAR071 direct block adapter")

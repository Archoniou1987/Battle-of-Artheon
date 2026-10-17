extends SceneTree

func _init() -> void:
	var template:Dictionary = TestFixtureLoader.load_json("res://data/test/item_generator_eff001_template.json")
	var generator := ItemGenerator.new(5150)
	var repository := ItemRepository.new()
	var first := CharacterState.new("CHAR_A", "Artheon A", 50)
	var second := CharacterState.new("CHAR_B", "Artheon B", 50)
	var item_a:Dictionary = generator.generate(template, "purple")
	var item_b:Dictionary = generator.generate(template, "purple")
	for pair in [[first,item_a],[second,item_b]]:
		var character:CharacterState = pair[0]
		var item:Dictionary = pair[1]
		repository.add_item(item); character.receive_item(String(item.instance_id), repository); character.equip("main_hand", String(item.instance_id), repository)
	var base := {"health":100,"mana":25}
	var fighter_a := CharacterCombatBuilder.build(first, repository, base)
	var fighter_b := CharacterCombatBuilder.build(second, repository, base)
	var stats_a := CharacterCombatBuilder.stats_snapshot(fighter_a)
	var stats_b := CharacterCombatBuilder.stats_snapshot(fighter_b)
	var ready_a := _ready(fighter_a, stats_a)
	var ready_b := _ready(fighter_b, stats_b)

	var state := CombatState.new(); state.add_combatant(fighter_a); state.add_combatant(fighter_b)
	var balance:Dictionary = TestFixtureLoader.load_json("res://data/balance/physical_combat.json")
	var effect_data:Dictionary = TestFixtureLoader.load_json("res://data/test/effects.json"); var effect_map := {}
	for effect in effect_data.get("effects", []): effect_map[String(effect.get("id", ""))] = effect
	balance["effects"] = effect_map
	var simulator := CombatSimulator.new(TestFixtureLoader.canonicalize_state(state), balance, 5150); simulator.max_rounds = 20
	var result := simulator.run_duel("CHAR_A", "CHAR_B")
	var combat_ran := int(result.get("rounds",0)) > 0 and state.event_log.size() > 0
	var ok := ready_a and ready_b and combat_ran
	print("CHARACTER_READY A=", ready_a, " B=", ready_b, " A_STATS=", stats_a)
	print("CHARACTER_READY B_STATS=", stats_b)
	print("CHARACTER_READY_COMBAT rounds=", result.get("rounds",0), " outcome=", result.get("outcome",""), " events=", state.event_log.size())
	print("CHARACTER_COMBAT_BUILDER_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _ready(fighter:CombatantState, snapshot:Dictionary)->bool:
	var effects:Array = fighter.combat_stats.get("weapon_on_hit_effects", [])
	var profiles:Array = fighter.combat_stats.get("weapon_profiles", [])
	return fighter.max_hp > 0 and not profiles.is_empty() and not effects.is_empty() and snapshot.has("stats") and snapshot.has("combat_stats") and snapshot.has("armour") and snapshot.has("abilities")

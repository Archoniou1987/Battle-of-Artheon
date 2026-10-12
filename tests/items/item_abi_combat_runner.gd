extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ITEM_ABI_HERO", "Item ABI Hero", 50)
	var sword := {"instance_id":"COMBAT-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["ABI001"]}
	ItemDurabilityService.initialize_item(sword, 50)
	repository.add_item(sword)
	hero.receive_item("COMBAT-SWORD-1", repository)
	var equipped: bool = hero.equip("main_hand", "COMBAT-SWORD-1", repository)
	var active: Array[String] = EquipmentAbilityLoadout.active_abilities(hero, repository)

	var state := CombatState.new()
	var first := CombatantState.new("ITEM_ABI_HERO", "Item ABI Hero", 50, 100, 25)
	var second := CombatantState.new("ITEM_ABI_ENEMY", "Enemy", 50, 100, 0)
	first.combat_stats = {"mana_regen":2,"weapon_profiles":[{"damage_min":2.0,"damage_max":2.0,"damage_type":"slashing"}],"hit_modifier":100.0}
	second.combat_stats = {"mana_regen":0,"weapon_profiles":[{"damage_min":2.0,"damage_max":2.0,"damage_type":"slashing"}],"hit_modifier":100.0}
	state.add_combatant(first)
	state.add_combatant(second)

	var definitions := AbilityCatalog.load_json("res://data/test/abilities.json")
	var item_loadouts := {"ITEM_ABI_HERO": active, "ITEM_ABI_ENEMY": []}
	var simulator := CombatSimulator.new(state, {}, 4242)
	simulator.max_rounds = 3
	simulator.ability_scheduler = AbilityScheduler.new(definitions, item_loadouts)
	var result: Dictionary = simulator.run_duel("ITEM_ABI_HERO", "ITEM_ABI_ENEMY")

	var abi_casts := 0
	var abi_damage := 0
	for event in state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and event.source_id == "ITEM_ABI_HERO" and String(event.payload.get("ability_id", "")) == "ABI001":
			abi_casts += 1
			abi_damage += int(event.result.get("hp_removed", 0))
	var item_source_ok: bool = active == ["ABI001"]
	var mana_spent: bool = int(result.get("first_mana", 25)) < 25
	var ok: bool = equipped and item_source_ok and abi_casts > 0 and abi_damage > 0 and mana_spent
	print("ITEM_ABI_COMBAT source=", active, " casts=", abi_casts, " damage=", abi_damage, " final_mana=", result.get("first_mana", -1))
	print("ITEM_ABI_COMBAT_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

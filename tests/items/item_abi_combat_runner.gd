extends SceneTree

func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ITEM_ABI_HERO", "Item ABI Hero", 50)
	var sword := {"instance_id":"COMBAT-SWORD-1","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["ABI001"]}
	repository.add_item(sword)
	hero.receive_item("COMBAT-SWORD-1", repository)
	var equipped: bool = hero.equip("main_hand", "COMBAT-SWORD-1", repository)

	var base_fighter := {"id":"ITEM_ABI_HERO","name":"Item ABI Hero","level":50,"hp":100,"mana":25,"mana_regen":2,"combat_stats":{},"stats":{},"main_hand":{"damage_min":2,"damage_max":2,"damage_type":"slashing"},"abilities":[]}
	var enemy := {"id":"ITEM_ABI_ENEMY","name":"Enemy","level":50,"hp":100,"mana":0,"mana_regen":0,"combat_stats":{},"stats":{},"main_hand":{"damage_min":2,"damage_max":2,"damage_type":"slashing"},"abilities":[]}
	var combat_fighter: Dictionary = EquipmentAbilityLoadout.apply_to_combat_data(base_fighter, hero, repository)
	var abilities: Dictionary = AbilityCatalog.load_json("res://data/test/abilities.json")
	var simulator := CombatSimulator.new(4242)
	var result: Dictionary = simulator.run_duel(combat_fighter, enemy, {}, abilities)
	var abi_casts := 0
	var abi_damage := 0
	for event in result.get("event_log", []):
		if String(event.get("kind", "")) == "Ability" and String(event.get("source_id", "")) == "ITEM_ABI_HERO":
			abi_casts += 1
			abi_damage += int(event.get("result", {}).get("final_damage", 0))
	var item_source_ok: bool = combat_fighter.get("abilities", []) == ["ABI001"]
	var mana_spent: bool = int(result.get("first_mana", 25)) < 25 or abi_casts > 0
	var ok: bool = equipped and item_source_ok and abi_casts > 0 and abi_damage > 0 and mana_spent
	print("ITEM_ABI_COMBAT source=", combat_fighter.get("abilities", []), " casts=", abi_casts, " damage=", abi_damage, " final_mana=", result.get("first_mana", -1))
	print("ITEM_ABI_COMBAT_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

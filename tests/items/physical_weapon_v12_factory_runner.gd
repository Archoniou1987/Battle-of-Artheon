extends SceneTree

## Run manually with Godot headless before enabling the CI gate.
## Confirms the shared v1.2 calculator creates real stable ITEMIDs for
## physical sword/dagger/axe/hammer archetypes without remapping PAR.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("PHYSICAL_V12_FAIL=",label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var archetypes := [
		"SWORD_DEF","SWORD_DODGE","SWORD_CRIT",
		"DAGGER_DEF","DAGGER_ATTACK","DAGGER_PEN",
		"AXE_DEF","AXE_ATTACK","AXE_SHIELD",
		"HAMMER_DEF","HAMMER_ATTACK"
	]
	var families := {"SWORD_":"sword","DAGGER_":"dagger","AXE_":"axe","HAMMER_":"hammer"}
	var seed_value := 20261104
	var rules: Dictionary = ItemTemplateGeneratorV12.new().rules
	var abilities: Dictionary = AbilityCatalog.load_json("res://data/abilities/catalog.json")
	for archetype_id in archetypes:
		var item := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value)
		_check(not item.is_empty(),archetype_id+"_generated")
		if item.is_empty():
			continue
		_check(String(item.get("instance_id","")).begins_with("ITEMID"),archetype_id+"_id")
		_check(String(item.get("slot",""))=="main_hand",archetype_id+"_slot")
		_check(item.get("equip_slots",[]) == WeaponHandPolicy.allowed_slots(archetype_id),archetype_id+"_hand_compatibility")
		_check(Array(item.get("abilities",[])).size()==4,archetype_id+"_runtime_abi_gate")
		for rule in Array(rules.get("weapon_archetypes", [])):
			var definition: Dictionary = rule
			if String(definition.get("id","")) == archetype_id:
				_check(Array(item["abilities"]) == Array(definition.get("abilities",[])),archetype_id+"_abi_refs_from_item_rules")
				for ability_id in item["abilities"]:
					_check(abilities.has(String(ability_id)),archetype_id+"_abi_exists_"+String(ability_id))
				break
		for prefix in families:
			if archetype_id.begins_with(String(prefix)):
				_check(String(item.get("weapon_class",""))==String(families[prefix]),archetype_id+"_family")
		var again := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value)
		_check(not again.is_empty() and item.get("damage",{})==again.get("damage",{}),archetype_id+"_stable_roll")
		_check(item.get("instance_id","")!=again.get("instance_id",""),archetype_id+"_unique_itemid")
		seed_value += 1
	for archetype_id in ["DAGGER_DEF","DAGGER_ATTACK","DAGGER_PEN"]:
		var offhand := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value,"OH")
		_check(not offhand.is_empty(),archetype_id+"_offhand_generated")
		_check(offhand.get("equip_slots",[])==["main_hand","off_hand"],archetype_id+"_universal")
		_check(Array(offhand.get("abilities",[])).size()==4,archetype_id+"_abi_stored_for_mh")
		_check(offhand.get("damage",{})==ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value,"MH").get("damage",{}),archetype_id+"_hand_neutral_damage")
		seed_value += 1
	# Selecting a mass-generator result must not roll its CORE/PAR again.
	var engine := ItemTemplateGeneratorV12.new()
	var batch := engine.generate({"archetypes":["DAGGER_ATTACK"],"weapon_hand":"MH","min_level":40,"max_level":40,"quality":"purple","count":1,"seed":202611041,"group_qualities":false})
	_check(bool(batch.get("ok",false)),"mass_v12_generated")
	if bool(batch.get("ok",false)):
		var row: Dictionary = batch["rows"][0]
		var instance := ItemV12InstanceFactory.instance_from_v12_row(row,202611041)
		_check(not instance.is_empty(),"mass_row_converted")
		if not instance.is_empty():
			_check(Dictionary(instance.get("damage",{})).get("min",-1) == (row["variant"]["damage"] as Array)[0],"mass_damage_same")
			_check(instance.get("v12_core_rolls",[]) == row["variant"].get("core_rolls",[]),"mass_core_same")
			_check(instance.get("v12_rarity_rolls",[]) == row["variant"].get("rolls",[]),"mass_bonus_same")
	# Check actual game combat profile: item_level must not silently fall
	# back to 1 for level-40 generated v1.2 weapons.
	var level_hero := CharacterState.new("V12_LEVEL","Weapon Level Test",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		level_hero.progression.base_stats[par_id] = 90
	var level_repo := ItemRepository.new()
	var level_item := ItemV12InstanceFactory.grant_weapon(level_hero,level_repo,"HAMMER_DEF",40,"purple",202611049)
	_check(not level_item.is_empty(),"level_item_generated")
	if not level_item.is_empty():
		_check(level_hero.equip("main_hand",String(level_item.get("instance_id","")),level_repo),"level_item_equipped")
		var level_fighter := CharacterCombatBuilder.build(level_hero,level_repo)
		_check(level_fighter != null,"level_combatant_built")
		if level_fighter != null:
			var profiles: Array = level_fighter.combat_stats.get("weapon_profiles",[])
			_check(not profiles.is_empty(),"level_weapon_profile")
			if not profiles.is_empty():
				_check(int(Dictionary(profiles[0]).get("item_level",-1))==40,"level_profile_preserved")
	# One instance remains identical while hand placement changes its effective
	# PAR and attack ranges. Stored ABI stay intact but are enabled only for MH.
	var switch_hero := CharacterState.new("V12_SWITCH","Hand Switch",40)
	for par_id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		switch_hero.progression.base_stats[par_id] = 90
	var switch_repo := ItemRepository.new()
	var switch_item := ItemV12InstanceFactory.grant_weapon(switch_hero,switch_repo,"DAGGER_ATTACK",40,"purple",202611050)
	_check(not switch_item.is_empty(),"switch_generated")
	if not switch_item.is_empty():
		var switch_id := String(switch_item["instance_id"])
		var original_damage: Dictionary = Dictionary(switch_item["damage"]).duplicate(true)
		var original_bonuses: Dictionary = Dictionary(switch_item["par_bonuses"]).duplicate(true)
		_check(switch_hero.equip("main_hand",switch_id,switch_repo),"switch_equip_mh")
		var mh_par := ParCalculationService.calculate(switch_hero,switch_repo)
		var mh_abilities := EquipmentAbilityLoadout.active_abilities(switch_hero,switch_repo)
		_check(mh_abilities.has("ABI406"),"switch_mh_has_abi")
		var main_range: Dictionary = mh_par.get("attack_ranges",{}).get("PAR050",{})
		_check(switch_hero.unequip("main_hand",switch_repo)==switch_id,"switch_unequip_mh")
		_check(switch_hero.equip("off_hand",switch_id,switch_repo),"switch_equip_oh")
		var oh_par := ParCalculationService.calculate(switch_hero,switch_repo)
		var off_range: Dictionary = oh_par.get("attack_ranges",{}).get("PAR051",{})
		_check(is_equal_approx(float(off_range.get("min",-1)),float(main_range.get("min",0))*0.75),"switch_oh_damage75")
		_check(not EquipmentAbilityLoadout.active_abilities(switch_hero,switch_repo).has("ABI406"),"switch_oh_no_abi")
		for par_id in original_bonuses:
			var expected := float(original_bonuses[par_id])*0.75
			var actual := float(Dictionary(oh_par.get("sources",{}).get(par_id,{})).get("equipment",0.0))
			_check(is_equal_approx(actual,expected),"switch_oh_par75_"+String(par_id))
		_check(int(Dictionary(oh_par.get("totals",{})).get("PAR057",0))==2,"switch_oh_keeps_attack_count")
		var unchanged := switch_repo.get_item(switch_id)
		_check(unchanged.get("damage",{})==original_damage and unchanged.get("par_bonuses",{})==original_bonuses,"switch_item_not_mutated")
		_check(switch_hero.unequip("off_hand",switch_repo)==switch_id,"switch_unequip_oh")
		_check(switch_hero.equip("main_hand",switch_id,switch_repo),"switch_return_mh")
		_check(EquipmentAbilityLoadout.active_abilities(switch_hero,switch_repo).has("ABI406"),"switch_mh_abi_restored")
	_check(ItemV12InstanceFactory.generate_weapon("AXE_DEF",40,"purple",1,"OH").is_empty(),"axe_no_oh")
	_check(not ItemV12InstanceFactory.generate_weapon("AXE_ATTACK",40,"purple",1,"OH").is_empty(),"axe_attack_oh")
	_check(not ItemV12InstanceFactory.generate_weapon("HAMMER_ATTACK",40,"purple",1,"OH").is_empty(),"hammer_attack_oh")
	_check(ItemV12InstanceFactory.generate_weapon("HAMMER_MAGIC",40,"purple",1).is_empty(),"magic_not_implemented")
	print("PHYSICAL_WEAPON_V12_FACTORY=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)

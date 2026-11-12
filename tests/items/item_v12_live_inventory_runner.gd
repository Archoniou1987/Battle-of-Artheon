extends SceneTree

## Real v1.2 items, not laboratory-only preview data.
func _initialize() -> void:
	call_deferred("_verify")

## A09: source-level boundary for the GAME routes (not the archived
## generator tests). This is deliberately part of the manual integration Gate.
## A future loot migration must explicitly use v1.2 and update this contract.
func _verify_generator_ownership(errors: Array[String]) -> void:
	if ItemTemplateGeneratorV12.RULE_PATH != "res://data/items/item_generator_v12_rules.json":
		errors.append("A09: v1.2 rule owner redirected")
	var production_routes := {
		"res://scenes/main/main.gd": [
			"res://scenes/debug/item_template_generator_v12.tscn"
		],
		"res://ui/inventory/inventory_screen.gd": [
			"ItemV12InstanceFactory.grant_weapon("
		],
		"res://core/items/item_v12_instance_factory.gd": [
			"ItemTemplateGeneratorV12.new()",
			"ItemTemplateGeneratorV12.RULE_PATH",
			"\"origin\": \"v12_game_generator\""
		],
		"res://core/map/map_combat_outcome_service.gd": [
			"NpcPossessionLootService"
		],
		"res://core/map/map_combat_settlement_service.gd": [
			"NpcPossessionLootService"
		],
		"res://core/loot/npc_possession_loot_service.gd": [
			"repository.get_item("
		]
	}
	for path in production_routes:
		if not FileAccess.file_exists(path):
			errors.append("A09: missing live generator route: " + String(path))
			continue
		var source := FileAccess.get_file_as_string(path)
		for required in Array(production_routes[path]):
			if not source.contains(String(required)):
				errors.append("A09: missing canonical route " + String(required) + " in " + String(path))
		for retired in ["ItemGenerator.new(", "LootService.new(", "CombatRewardService.", "ChestService."]:
			if source.contains(retired):
				errors.append("A09: legacy v1 generator reintroduced in live route " + String(path))
	var menu_source := FileAccess.get_file_as_string("res://scenes/main/main.gd")
	if menu_source.contains("res://scenes/debug/item_generator_lab.tscn"):
		errors.append("A09: archived v1 item lab exposed as active debug generator")
	var legacy := FileAccess.get_file_as_string("res://core/loot/loot_service.gd")
	if not legacy.contains("generator: ItemGenerator"):
		errors.append("A09: legacy loot test adapter changed; review ownership before migration")


## A12: the WORLD reward path selects the NPC's existing v1.2 ITEMID.
## No second generator, PAR reroll, or replacement instance may be involved.
func _verify_v12_npc_possession_reward(errors: Array[String]) -> void:
	var npc_catalog: Dictionary = TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_template := NpcState.new(Dictionary(Array(npc_catalog.get("npcs",[]))[2]))
	var npc := NpcInstance.new("A12_V12_NPC_001",npc_template)
	var repository := ItemRepository.new()
	var item := ItemV12InstanceFactory.generate_weapon("SWORD_DEF",40,"purple",202611067)
	if item.is_empty():
		errors.append("A12: canonical v1.2 NPC test item unavailable")
		return
	var item_id := String(item.get("instance_id",""))
	if not repository.add_item(item) or not npc.receive_item(item_id,repository):
		errors.append("A12: NPC cannot own the original v1.2 instance")
		return
	var drops := NpcPossessionLootService.new(42).roll_drops(npc,repository,{"purple":100.0})
	if drops.size()!=1:
		errors.append("A12: NPC possession must select one original item, not reroll")
		return
	var drop: Dictionary = drops[0]
	if String(drop.get("instance_id",""))!=item_id or drop.get("damage",{})!=item.get("damage",{}) or drop.get("par_bonuses",{})!=item.get("par_bonuses",{}) or String(drop.get("loot_source_id",""))!=npc.instance_id:
		errors.append("A12: NPC reward must preserve exact v1.2 ID and rolls")
		return
	var recipient := CharacterState.new("A12_REWARD_PLAYER","Reward Test",40)
	var pool := EncounterLootPool.new()
	if not pool.add_drop(item_id,npc.instance_id):
		errors.append("A12: world reward pool rejected original item ID")
		return
	pool.assign_all(recipient.character_id)
	if not pool.claim(item_id,recipient,repository) or not recipient.inventory.owns(item_id):
		errors.append("A12: reward claim did not transfer original v1.2 instance")
		return
	if pool.claim(item_id,recipient,repository):
		errors.append("A12: world reward allows duplicate claim")
	var saved: Dictionary = repository.get_item(item_id)
	if saved.get("damage",{})!=item.get("damage",{}) or saved.get("par_bonuses",{})!=item.get("par_bonuses",{}):
		errors.append("A12: claimed reward changed original v1.2 item rolls")


func _verify() -> void:
	var errors: Array[String] = []
	_verify_generator_ownership(errors)
	_verify_v12_npc_possession_reward(errors)
	var hero := CharacterState.new("V12_BAG_HERO","Hero",40)
	var repo := ItemRepository.new()
	var created_ids: Array[String] = []
	for spec in [
		["SWORD_DEF",202611041],
		["SWORD_DODGE",202611042],
		["SWORD_CRIT",202611043]
	]:
		var archetype := String(spec[0])
		var item := ItemV12InstanceFactory.grant_sword(hero,repo,archetype,40,"purple",int(spec[1]))
		if item.is_empty():
			errors.append("Cannot grant "+archetype)
			continue
		var instance_id := String(item["instance_id"])
		created_ids.append(instance_id)
		if not instance_id.begins_with("ITEMID") or not hero.inventory.owns(instance_id) or not repo.has_item(instance_id):
			errors.append("Missing unique persistent ownership: "+archetype)
		var resolved := repo.get_item(instance_id)
		if String(resolved.get("generated_from_template","")) != archetype or int(resolved.get("item_level",0)) != 40 or String(resolved.get("rarity","")) != "purple":
			errors.append("Variant metadata lost: "+archetype)
		if String(resolved.get("weapon_class","")) != "sword" or not Array(resolved.get("equip_slots",[])).has("main_hand"):
			errors.append("Not equipable as real MH sword: "+archetype)
		if Dictionary(resolved.get("par_stats",{})).get("PAR057",null) != 1:
			errors.append("Missing canonical PAR057: "+archetype)
		if not ParCalculationService.valid_damage_range(resolved.get("damage",{})):
			errors.append("Damage packet invalid: "+archetype)
		if String(resolved.get("template_id","")) != "":
			errors.append("Self-contained dynamic instance must not reference a missing static template")
		if Array(resolved.get("v12_core_rolls",[])).size() != 1 or Array(resolved.get("v12_rarity_rolls",[])).size() != 3:
			errors.append("Wrong Lv40 epic PAR cell allocation: "+archetype)
		for par_id in Dictionary(resolved.get("par_bonuses",{})):
			if not ParCalculationService.registry().has(String(par_id)):
				errors.append("Unregistered runtime PAR: "+String(par_id))
	if created_ids.size() != 3 or created_ids[0] == created_ids[1] or created_ids[0] == created_ids[2] or created_ids[1] == created_ids[2]:
		errors.append("Distinct templates must have unique instance IDs")
	var replay := ItemV12InstanceFactory.grant_sword(hero,repo,"SWORD_DEF",40,"purple",202611041)
	if replay.is_empty() or created_ids.has(String(replay.get("instance_id",""))):
		errors.append("Same seed must still create a NEW instance")
	if not ItemV12InstanceFactory.generate_sword("SWORD_DEF",30,"purple",100).is_empty():
		errors.append("Epic must be gated at Lv40")
	if not ItemV12InstanceFactory.generate_sword("SWORD_MAGIC",40,"purple",100).is_empty():
		errors.append("Physical generator must reject magical archetype")
	var restored_repo := ItemRepository.from_dict(repo.to_dict())
	var restored_bag := InventoryState.from_dict(hero.inventory.to_dict(),restored_repo)
	for instance_id in created_ids:
		if not restored_bag.owns(instance_id) or restored_repo.get_item(instance_id).is_empty():
			errors.append("Instance not preserved after save/restore: "+instance_id)
	if errors.is_empty():
		print("V12_LIVE_ITEM_INVENTORY=PASS · 3 Lv40 epics, unique IDs, real bag ownership and round-trip")
	else:
		for msg in errors:
			push_error("V12_LIVE_ITEM_INVENTORY=FAIL: "+msg)
	quit(0 if errors.is_empty() else 1)

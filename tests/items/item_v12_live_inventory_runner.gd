extends SceneTree

## Real v1.2 items, not laboratory-only preview data.
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var errors: Array[String] = []
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

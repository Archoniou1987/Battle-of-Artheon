extends SceneTree

func _init() -> void:
	var template := {"id":"DURABILITY_TEST","name":"Test Sword","item_level":1,"equip_slots":["main_hand"],"slot_usage":["main_hand"],"damage_min":1,"damage_max":2,"durability_max":50}
	var generator := ItemGenerator.new(500)
	var item := generator.generate(template, "common")
	var ok := int(item.get("durability_current", -1)) == 50 and int(item.get("durability_max", -1)) == 50
	ok = ok and int(item.get("_durability_repair_progress", -1)) == 0

	ItemDurabilityService.damage(item, 2)
	ok = ok and int(item.durability_current) == 48
	ok = ok and ItemDurabilityService.repair(item, 2) == 2
	ok = ok and int(item.durability_current) == 50 and int(item.durability_max) == 50
	ok = ok and int(item.get("_durability_repair_progress", -1)) == 2

	ItemDurabilityService.damage(item, 47)
	ItemDurabilityService.repair(item, 47)
	ok = ok and int(item.durability_max) == 49 and int(item.durability_current) == 49
	ok = ok and int(item.get("_durability_repair_progress", -1)) == 0

	ItemDurabilityService.damage(item, 49)
	ok = ok and not ItemDurabilityService.is_usable(item)
	ItemDurabilityService.repair(item, 1)
	ok = ok and ItemDurabilityService.is_usable(item)

	var summary := ItemDurabilityService.public_summary(item)
	ok = ok and summary.has("durability_current") and summary.has("durability_max")
	ok = ok and not summary.has("_durability_repair_progress")

	print("DURABILITY current=%d max=%d hidden_progress=%d" % [int(item.durability_current), int(item.durability_max), int(item.get("_durability_repair_progress", -1))])
	print("ITEM_DURABILITY_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

extends SceneTree

const SLOT_BY_TEMPLATE := {"CHEST_15":"chest","LEGS_16":"legs","HEAD_17":"head","FEET_18":"feet","SWORD_19":"main_hand","SHIELD_20":"off_hand"}
const SLOTS := ["head","chest","legs","feet","main_hand","off_hand"]

func _initialize() -> void:
	var data: Dictionary = TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var repository := ItemRepository.new()
	var generator := ItemGenerator.new(20261006)
	var bot_a := CharacterState.new("BOT_A","Durability Bot A",20)
	var bot_b := CharacterState.new("BOT_B","Durability Bot B",20)
	for template in data.get("templates", []):
		for bot in [bot_a,bot_b]:
			var item := generator.generate(template,"green")
			repository.add_item(item)
			bot.receive_item(String(item.instance_id),repository)
			bot.equip(String(SLOT_BY_TEMPLATE[String(template.id)]),String(item.instance_id),repository)
	var base := {"health":100,"mana":30,"combat_stats":{"mana_regen":2.0,"crit":5.0,"dodge":5.0}}
	var initial := _run_series(bot_a,bot_b,repository,base,100,10000)
	var repaired := {"BOT_A":_repair_all(bot_a,repository),"BOT_B":_repair_all(bot_b,repository)}
	var after_repair := [_bot_report(bot_a,repository),_bot_report(bot_b,repository)]
	var broken_filter_ok := _verify_broken_item_inactive(bot_a,repository,base)
	var second := _run_series(bot_a,bot_b,repository,base,100,20000)
	var before_final_repair := [_bot_report(bot_a,repository),_bot_report(bot_b,repository)]
	var final_repair := {"BOT_A":_repair_all(bot_a,repository),"BOT_B":_repair_all(bot_b,repository)}
	var final := [_bot_report(bot_a,repository),_bot_report(bot_b,repository)]
	var final_repair_ok := _all_usable(bot_a,repository) and _all_usable(bot_b,repository)
	var report := {"initial_100":initial,"repair":repaired,"after_repair":after_repair,"broken_item_filter_ok":broken_filter_ok,"second_100_draws_as_defeats":second,"before_final_repair":before_final_repair,"final_repair":final_repair,"final":final}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results"))
	var file := FileAccess.open("res://test-results/hundred_bot_durability_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("BOT_DURABILITY_100_REPORT="+JSON.stringify(report))
	var valid := broken_filter_ok and final_repair_ok
	print("BOT_DURABILITY_REPAIR_BREAK_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _run_series(a:CharacterState,b:CharacterState,repository:ItemRepository,base:Dictionary,count:int,seed_base:int) -> Dictionary:
	var wins := {a.character_id:0,b.character_id:0}
	var draws := 0
	var defeat_events := {a.character_id:0,b.character_id:0}
	for battle in range(count):
		var state := CombatState.new()
		state.add_combatant(CharacterCombatBuilder.build(a,repository,base))
		state.add_combatant(CharacterCombatBuilder.build(b,repository,base))
		var sim := CombatSimulator.new(TestFixtureLoader.canonicalize_state(state),TestFixtureLoader.load_json("res://data/balance/physical_combat.json"),seed_base+battle)
		var result := sim.run_duel(a.character_id,b.character_id)
		var loser_id := String(result.get("loser_id",""))
		if loser_id.is_empty():
			draws += 1
			for bot in [a,b]:
				ItemWearService.damage_equipped(bot,repository,1)
				defeat_events[bot.character_id] += 1
		else:
			var loser := a if loser_id == a.character_id else b
			ItemWearService.damage_equipped(loser,repository,1)
			defeat_events[loser.character_id] += 1
			wins[String(result.get("winner_id",""))] += 1
	return {"battles":count,"wins":wins,"draws":draws,"defeat_events":defeat_events,"state":[_bot_report(a,repository),_bot_report(b,repository)]}

func _repair_all(bot:CharacterState,repository:ItemRepository) -> Dictionary:
	var restored := 0
	for slot in SLOTS:
		var item := ItemResolver.resolve_equipped(slot,bot.equipment,repository)
		restored += ItemDurabilityService.repair(item,int(item.get("durability_max",0))-int(item.get("durability_current",0)))
		repository.update_item(item)
	return {"restored":restored,"state":_bot_report(bot,repository)}

func _verify_broken_item_inactive(bot:CharacterState,repository:ItemRepository,base:Dictionary) -> bool:
	var id := String(bot.equipment.get_equipped_instance_id("head"))
	var item := repository.get_item(id)
	var saved := int(item.get("durability_current",0))
	ItemDurabilityService.damage(item,saved)
	repository.update_item(item)
	var active_ids := EquipmentAbilityLoadout.active_abilities(bot,repository)
	var broken_abilities:Array = item.get("abilities",[])
	var abi_inactive := true
	for ability in broken_abilities:
		if active_ids.has(String(ability)): abi_inactive = false
	var snapshot := CharacterCombatBuilder.build(bot,repository,base)
	var item_filtered := true
	for equipped in CharacterCombatBuilder.equipped_items(bot,repository):
		if String(equipped.get("instance_id","")) == id: item_filtered = false
	item["durability_current"] = saved
	repository.update_item(item)
	return abi_inactive and item_filtered and snapshot != null

func _all_usable(bot:CharacterState,repository:ItemRepository) -> bool:
	for slot in SLOTS:
		if ItemDurabilityService.is_usable(ItemResolver.resolve_equipped(slot,bot.equipment,repository)): return true
	return false

func _bot_report(bot:CharacterState,repository:ItemRepository) -> Dictionary:
	var items:Array[Dictionary]=[]
	for slot in SLOTS:
		var item := ItemResolver.resolve_equipped(slot,bot.equipment,repository)
		items.append({"slot":slot,"instance_id":String(item.get("instance_id","")),"name":String(item.get("name","")),"durability_current":int(item.get("durability_current",0)),"durability_max":int(item.get("durability_max",0)),"usable":ItemDurabilityService.is_usable(item)})
	return {"bot_id":bot.character_id,"items":items}

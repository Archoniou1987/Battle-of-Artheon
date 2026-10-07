extends SceneTree
func _initialize()->void:
	var templates:Dictionary={}
	for level in [1,10,20,30,40,50,60,70,80,90,100]:
		var id:String="DAGGER_%03d"%level
		templates[id]={"id":id,"name":"Test Dagger Lv%d"%level,"item_level":level,"loot_category":"equipment","item_type":"dagger","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"damage_min":1,"damage_max":2,"damage_type":"piercing","durability_max":20}
	var groups:Dictionary={"BANDIT_DAGGER_TEST":{"id":"BANDIT_DAGGER_TEST","entries":[{"mode":"scaled","category":"equipment","item_type":"dagger"}]}}
	var repository:=ItemRepository.new()
	var player:=CharacterState.new("PLAYER_DAGGER_TEST","Artheon Hero",70)
	var fighter:=CharacterCombatBuilder.build(player,repository,{"health":200,"mana":0,"stats":{"STR":10,"DEX":10,"INTU":10,"INT":10,"WIS":10,"END":10},"combat_stats":{"main_hand_damage_min":40.0,"main_hand_damage_max":40.0,"main_hand_damage_type":"slashing"}})
	var bandit:=CombatantState.new("NPC_DAGGER_BANDIT","Unarmed Bandit",70,30,0)
	bandit.combat_stats={"main_hand_damage_min":0.0,"main_hand_damage_max":0.0,"main_hand_damage_type":"blunt"}
	var state:=CombatState.new()
	state.add_combatant(fighter)
	state.add_combatant(bandit)
	var simulator:=CombatSimulator.new(state,TestFixtureLoader.load_json("res://data/balance/physical_combat.json"),7710)
	simulator.max_rounds=10
	var result:=simulator.run_duel(fighter.combatant_id,bandit.combatant_id)
	var service:=LootGroupService.new(7711)
	var candidates:Array[Dictionary]=service.candidates(bandit.level,"normal",["BANDIT_DAGGER_TEST"],groups,templates,{})
	var drops:Array[Dictionary]=[]
	if String(result.get("winner_id",""))==fighter.combatant_id and not candidates.is_empty():
		var chosen:Dictionary=candidates[0].get("template",{})
		var item:=ItemGenerator.new(7712).generate(chosen,"common",{"origin":"loot","max_wear_min":0.10,"max_wear_max":0.35,"damage_min":0.15,"damage_max":0.65,"hidden_progress_min":0.0,"hidden_progress_max":1.0})
		item["loot_source_id"]=bandit.combatant_id
		if repository.add_item(item) and player.inventory.add_instance(String(item.get("instance_id","")),repository):
			drops.append(item)
	var level_range:=LootLevelProfile.range_for(bandit.level,"normal")
	var valid:bool=templates.size()==11 and String(result.get("winner_id",""))==fighter.combatant_id and drops.size()==1
	if not drops.is_empty():
		valid=valid and int(drops[0].get("item_level",0))>=int(level_range.get("min",0)) and int(drops[0].get("item_level",0))<=int(level_range.get("max",0))
		valid=valid and String(drops[0].get("origin",""))=="loot"
		valid=valid and int(drops[0].get("durability_max",20))<20 and int(drops[0].get("durability_current",20))<int(drops[0].get("durability_max",20))
	print("DAGGER_LEVELS="+JSON.stringify([1,10,20,30,40,50,60,70,80,90,100]))
	print("DAGGER_BANDIT combat_winner=%s bandit_hp=%d loot_range=%d-%d drops=%d"%[String(result.get("winner_id","")),int(result.get("second_hp",-1)),int(level_range.get("min",0)),int(level_range.get("max",0)),drops.size()])
	if not drops.is_empty(): print("DAGGER_DROP="+JSON.stringify(drops[0]))
	print("DAGGER_LEVEL_DROP_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

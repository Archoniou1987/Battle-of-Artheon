extends SceneTree
func _initialize()->void:
	var templates:Dictionary={}
	for level in [1,10,20,30,40,50,60,70,80,90,100]:
		var id:String="DAGGER_%03d"%level
		templates[id]={"id":id,"name":"Test Dagger Lv%d"%level,"item_level":level,"loot_category":"equipment","item_type":"dagger","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"damage_min":1,"damage_max":2,"damage_type":"piercing","durability_max":20}
	var groups:Dictionary={"BANDIT_DAGGER_TEST":{"id":"BANDIT_DAGGER_TEST","entries":[{"mode":"scaled","category":"equipment","item_type":"dagger"}]}}
	var repository:=ItemRepository.new()
	var player:=CharacterState.new("PLAYER_DAGGER_TEST","Artheon Hero",70)
	TestFixtureLoader.equip_character_weapon(player, repository, 40)
	var fighter:=CharacterCombatBuilder.build(player,repository,{"health":200,"mana":0})
	var bandit:=TestFixtureLoader.new_combatant("NPC_DAGGER_BANDIT","Unarmed Bandit",70,30,0)
	bandit.combat_stats.merge({"weapon_profiles":[{"damage_min":0.0,"damage_max":0.0,"damage_type":"blunt"}]}, true)
	var state:=CombatState.new()
	state.add_combatant(fighter)
	state.add_combatant(bandit)
	var simulator:=CombatSimulator.new(TestFixtureLoader.canonicalize_state(state),TestFixtureLoader.load_json("res://data/balance/physical_combat.json"),7710)
	simulator.max_rounds=10
	var result:=simulator.run_duel(fighter.combatant_id,bandit.combatant_id)
	var attack_details:Array[Dictionary]=[]
	var attack_outcomes:Dictionary={}
	var attacks_by_source:Dictionary={}
	for event in simulator.state.event_log:
		if event.kind != CombatEvent.Kind.ATTACK:
			continue
		var outcome:=String(event.result.get("outcome","missing_outcome"))
		attack_outcomes[outcome]=int(attack_outcomes.get(outcome,0))+1
		attacks_by_source[event.source_id]=int(attacks_by_source.get(event.source_id,0))+1
		if event.source_id==fighter.combatant_id and attack_details.size()<10:
			attack_details.append({"outcome":outcome,"hit_chance":event.result.get("hit_chance",-1),"hit_roll":event.result.get("hit_roll",-1),"weapon_skill_hit_penalty":event.result.get("weapon_skill_hit_penalty",-1),"damage":event.result.get("raw_damage",-1)})
	print("DAGGER_COMBAT_DIAGNOSTICS="+JSON.stringify({
		"rounds":result.get("rounds",-1),
		"fighter_level":fighter.level,
		"bandit_level":bandit.level,
		"base_hit":simulator.engine._hit_chance(fighter.level-bandit.level),
		"fighter_hit_bonus":CombatModifierService.effective_percent(fighter,"hit_chance_rating",simulator.state.round_number),
		"first_hp":result.get("first_hp",-1),
		"second_hp":result.get("second_hp",-1),
		"outcome":result.get("outcome",""),
		"attack_outcomes":attack_outcomes,
		"player_attacks":attack_details,
		"attacks_by_source":attacks_by_source,
		"fighter_par":ParCombatContract.validate(fighter),
		"bandit_par":ParCombatContract.validate(bandit),
		"fighter_profiles":WeaponAttackProfile.all(fighter),
		"bandit_profiles":WeaponAttackProfile.all(bandit)
	}))
	var service:=LootGroupService.new(7711)
	var candidates:Array[Dictionary]=service.candidates(bandit.level,"normal",["BANDIT_DAGGER_TEST"],groups,templates,{})
	var drops:Array[Dictionary]=[]
	var pool:=EncounterLootPool.new()
	if String(result.get("winner_id",""))==fighter.combatant_id and not candidates.is_empty():
		var chosen:Dictionary=candidates[0].get("template",{})
		var item:=ItemGenerator.new(7712).generate(chosen,"common",{"origin":"loot","max_wear_min":0.10,"max_wear_max":0.35,"damage_min":0.15,"damage_max":0.65,"hidden_progress_min":0.0,"hidden_progress_max":1.0})
		item["loot_source_id"]=bandit.combatant_id
		if repository.add_item(item) and pool.add_drop(String(item.get("instance_id","")),bandit.combatant_id):
			drops.append(item)
	pool.assign_all(player.character_id)
	var level_range:=LootLevelProfile.range_for(bandit.level,"normal")
	var valid:bool=templates.size()==11 and String(result.get("winner_id",""))==fighter.combatant_id and drops.size()==1
	valid=valid and player.bag_item_count()==0 and pool.available_for(player.character_id).size()==1
	if not drops.is_empty():
		valid=valid and int(drops[0].get("item_level",0))>=int(level_range.get("min",0)) and int(drops[0].get("item_level",0))<=int(level_range.get("max",0))
		valid=valid and String(drops[0].get("origin",""))=="loot"
		valid=valid and int(drops[0].get("durability_max",20))<20 and int(drops[0].get("durability_current",20))<int(drops[0].get("durability_max",20))
	for item_id in pool.item_ids().duplicate():
		valid=valid and pool.claim(item_id,player,repository)
		valid=valid and not pool.claim(item_id,player,repository)
	valid=valid and player.bag_item_count()==1 and pool.item_ids().is_empty()
	print("DAGGER_LEVELS="+JSON.stringify([1,10,20,30,40,50,60,70,80,90,100]))
	print("DAGGER_BANDIT combat_winner=%s bandit_hp=%d loot_range=%d-%d drops=%d"%[String(result.get("winner_id","")),int(result.get("second_hp",-1)),int(level_range.get("min",0)),int(level_range.get("max",0)),drops.size()])
	if not drops.is_empty(): print("DAGGER_DROP="+JSON.stringify(drops[0]))
	print("DAGGER_LEVEL_DROP_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

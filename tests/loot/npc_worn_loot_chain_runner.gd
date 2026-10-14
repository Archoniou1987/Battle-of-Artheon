extends SceneTree
func _initialize() -> void:
	var td:=TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var ld:=TestFixtureLoader.load_json("res://data/test/loot_tables.json")
	var templates:Dictionary={}
	for raw in td.get("templates",[]):
		var t:=raw as Dictionary
		templates[String(t.get("id",""))]=t
	var table:Dictionary=(ld.get("loot_tables",[]) as Array)[0] as Dictionary
	var repository:=ItemRepository.new()
	var player:=CharacterState.new("PLAYER_CHAIN","Chain Hero",20)
	TestFixtureLoader.equip_character_weapon(player, repository, 35)
	var base:={"health":160,"mana":30}
	var npc:=TestFixtureLoader.new_combatant("NPC_WORN_BANDIT_001","Worn Bandit",10,25,0)
	npc.combat_stats={"weapon_profiles":[{"damage_min":1.0,"damage_max":1.0,"damage_type":"slashing"}]}
	var state:=CombatState.new()
	state.add_combatant(CharacterCombatBuilder.build(player,repository,base))
	state.add_combatant(npc)
	var sim:=CombatSimulator.new(TestFixtureLoader.canonicalize_state(state),TestFixtureLoader.load_json("res://data/balance/physical_combat.json"),7070)
	sim.max_rounds=10
	var result:=sim.run_duel(player.character_id,npc.combatant_id)
	var pool:=CombatRewardService.create_duel_loot_pool(result,npc.combatant_id,player,table,templates,ItemGenerator.new(20261006),repository,LootService.new(4242))
	var drops:Array[Dictionary]=[]
	for item_id in pool.item_ids():
		drops.append(repository.get_item(item_id))
	var valid:=not pool.item_ids().is_empty() and player.bag_item_count()==0
	valid=valid and String(result.get("winner_id",""))==player.character_id and drops.size()==2
	for item in drops:
		var maximum:=int(item.get("durability_max",0))
		var current:=int(item.get("durability_current",0))
		valid=valid and String(item.get("origin",""))=="loot"
		valid=valid and maximum>=33 and maximum<=45 and current>=0 and current<maximum
		valid=valid and String(item.get("loot_source_id",""))==npc.combatant_id
		valid=valid and pool.available_for(player.character_id).has(String(item.get("instance_id","")))
		valid=valid and repository.has_item(String(item.get("instance_id","")))
	for item_id in pool.item_ids().duplicate():
		valid=valid and pool.claim(item_id,player,repository)
	valid=valid and player.bag_item_count()==2 and pool.item_ids().is_empty()
	print("NPC_LOOT_CONDITION_CHAIN outcome=%s drops=%d" % [String(result.get("outcome","")),drops.size()])
	for item in drops:
		print("NPC_LOOT_CONDITION_ITEM "+JSON.stringify(ItemDurabilityService.public_summary(item)))
	print("NPC_LOOT_CONDITION_CHAIN_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

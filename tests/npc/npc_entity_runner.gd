extends SceneTree
func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var repo:=NpcRepository.new()
	repo.load_definitions(doc)
	var ids:=["NPC001","NPC002","NPC003","NPC004","NPC005"]
	var valid:=repo.size()==5
	for id in ids:
		var npc:=repo.get_npc(id)
		valid=valid and npc!=null and npc.npc_id==id and not npc.loot_table_id.is_empty()
		var fighter:=NpcCombatBuilder.build(npc)
		valid=valid and fighter.combatant_id==id and fighter.level==npc.level and fighter.max_hp>0
	var chief:=repo.get_npc("NPC005")
	valid=valid and chief.rank=="elite" and "ABI001" in chief.abilities
	print("NPC_ENTITY_COUNT=%d chief=%s rank=%s hp=%d" % [repo.size(),chief.display_name,chief.rank,NpcCombatBuilder.build(chief).max_hp])
	print("NPC_ENTITY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

extends SceneTree
func _initialize()->void:
	var doc:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var repo:=NpcRepository.new(); repo.load_definitions(doc)
	var bandit_template:=repo.get_npc("NPC003")
	var bandit:=NpcInstance.new("WORLD_BANDIT_001",bandit_template)
	var map:=TacticalMapState.new(12,12)
	var bridge:=MapNpcBridge.new()
	var valid:=bridge.register_npc(map,bandit,Vector2i(5,5))
	valid=valid and map.entity_positions["WORLD_BANDIT_001"]==Vector2i(5,5)
	var found:=bridge.npc_at(map,Vector2i(5,5))
	valid=valid and found.size()==1 and found[0]==bandit
	var encounter:=bridge.encounter_at(map,Vector2i(5,5))
	valid=valid and bool(encounter.get("ok",false)) and encounter.get("npc")==bandit
	valid=valid and String(encounter.get("npc_template_id",""))=="NPC003"
	valid=valid and map.add_object("CHEST_WORLD_001",Vector2i(6,5))
	valid=valid and map.add_object("ORE_WORLD_001",Vector2i(6,5))
	valid=valid and map.cell(Vector2i(6,5)).object_ids.size()==2
	valid=valid and map.remove_object("CHEST_WORLD_001",Vector2i(6,5))
	valid=valid and map.cell(Vector2i(6,5)).object_ids==["ORE_WORLD_001"]
	var player_ok:=map.place_entity("PLAYER",Vector2i(4,5))
	var step:=map.move_entity("PLAYER",Vector2i(5,5))
	valid=valid and player_ok and bool(step.get("ok",false))
	var contact:=bridge.encounter_at(map,map.entity_positions["PLAYER"])
	valid=valid and bool(contact.get("ok",false)) and String(contact.get("npc_instance_id",""))=="WORLD_BANDIT_001"
	print("WORLD_OBJECT npc=%s template=%s objects=%s"%[contact.get("npc_instance_id",""),contact.get("npc_template_id",""),map.cell(Vector2i(6,5)).object_ids])
	print("WORLD_OBJECT_INTERACTION_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

extends SceneTree

func _initialize()->void:
	var td:=TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var templates:Dictionary={}
	for raw in td.get("templates",[]):
		var x:=raw as Dictionary
		templates[String(x.get("id",""))]=x
	var nd:=TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var nr:=NpcRepository.new()
	nr.load_definitions(nd)
	var npc:=NpcInstance.new("NPCINST000001",nr.get_npc("NPC003"))
	var items:=ItemRepository.new()
	var gen:=ItemGenerator.new(150015)
	var sword:=gen.generate(templates["SWORD_19"],"blue",{"origin":"loot","max_wear_min":0.10,"max_wear_max":0.10,"damage_min":0.20,"damage_max":0.20})
	var helm:=gen.generate(templates["HEAD_17"],"common",{"origin":"loot"})
	var boots:=gen.generate(templates["FEET_18"],"green",{"origin":"loot"})
	for item in [sword,helm,boots]:
		items.add_item(item)
		npc.receive_item(String(item.instance_id),items)
	var equipped_ok:=npc.equip("main_hand",String(sword.instance_id),items) and npc.equip("head",String(helm.instance_id),items)
	var player:=CharacterState.new("PLAYER_LOOT","Loot Hero",15)
	var chances:={"poor":30.0,"common":20.0,"green":10.0,"blue":100.0,"purple":1.0}
	var drops:=NpcPossessionLootService.new(5151).roll(npc,items,player,chances)
	var ids:Array=[]
	for item in drops: ids.append(String(item.instance_id))
	var valid:=equipped_ok and drops.size()==1 and ids.has(String(sword.instance_id)) and player.inventory.owns(String(sword.instance_id))
	valid=valid and not player.inventory.owns(String(helm.instance_id)) and not player.inventory.owns(String(boots.instance_id))
	print("NPC_POSSESSION before equipment=[%s,%s] bag=%s" % [String(sword.instance_id),String(helm.instance_id),String(boots.instance_id)])
	print("NPC_POSSESSION blue_sword_condition=%d/%d" % [int(sword.durability_current),int(sword.durability_max)])
	print("NPC_POSSESSION roll_chances="+JSON.stringify(chances))
	print("NPC_POSSESSION drops="+JSON.stringify(ids))
	print("NPC_POSSESSION_SAME_INSTANCE=%s" % str(ids.has(String(sword.instance_id))))
	print("NPC_POSSESSION_LOOT_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

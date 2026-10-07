extends SceneTree

const SLOT_BY_TEMPLATE := {"CHEST_15":"chest","LEGS_16":"legs","HEAD_17":"head","FEET_18":"feet","SWORD_19":"main_hand","SHIELD_20":"off_hand"}
const QUALITIES := ["common","green","blue","purple"]

func _init() -> void:
	var data:Dictionary = TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	var generator := ItemGenerator.new(20261005)
	var repository := ItemRepository.new()
	var bots:Array[CharacterState] = []
	for i in range(10): bots.append(CharacterState.new("BOT_%02d" % (i+1), "Potential Player %02d" % (i+1), 20))
	var rng := RandomNumberGenerator.new(); rng.seed = 20261005
	var all_items:Array[Dictionary] = []
	for template in data.get("templates", []):
		var pool:Array[Dictionary] = []
		for i in range(10):
			var quality := String(QUALITIES[rng.randi_range(0, QUALITIES.size()-1)])
			pool.append(generator.generate(template, quality))
		pool.shuffle()
		for i in range(10):
			var item:Dictionary = pool[i]; var bot:CharacterState = bots[i]
			repository.add_item(item); bot.receive_item(String(item.instance_id), repository)
			var equipped := bot.equip(String(SLOT_BY_TEMPLATE[String(template.id)]), String(item.instance_id), repository)
			if not equipped: _fail("equip failed " + String(template.id)); return
			all_items.append(item)
	var base := {"health":100,"mana":30,"stats":{"STR":5,"DEX":5,"INTU":5,"INT":5,"WIS":5,"END":5},"combat_stats":{"mana_regen":2.0,"crit":5.0,"dodge":5.0}}
	var snapshots:Array[Dictionary] = []
	for bot in bots:
		var fighter := CharacterCombatBuilder.build(bot, repository, base)
		var snapshot := CharacterCombatBuilder.stats_snapshot(fighter)
		snapshot["equipment"] = _equipment_summary(bot, repository)
		snapshots.append(snapshot)
		print("PLAYER_STATS ", JSON.stringify(snapshot))
	var valid := all_items.size()==60 and snapshots.size()==10
	for snapshot in snapshots:
		var cs:Dictionary=snapshot.combat_stats; var eq:Dictionary=snapshot.equipment
		valid = valid and eq.size()==6 and int(snapshot.max_hp)>100 and cs.has("main_hand_damage_min") and float(cs.get("dodge",0))>0 and float(cs.get("auto_block",0))>0 and not (snapshot.armour as Dictionary).is_empty()
	print("TEN_PLAYER_STATS items=", all_items.size(), " players=", snapshots.size(), " entities_alive=", valid)
	print("TEN_PLAYER_STATS_TEST=", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)

func _equipment_summary(bot:CharacterState, repository:ItemRepository)->Dictionary:
	var result:Dictionary={}
	for slot in ["head","chest","legs","feet","main_hand","off_hand"]:
		var item:=ItemResolver.resolve_equipped(slot, bot.equipment, repository)
		result[slot]={"instance_id":item.get("instance_id",""),"name":item.get("name",""),"level":item.get("item_level",0),"quality":item.get("quality","")}
	return result

func _fail(message:String)->void:
	print("TEN_PLAYER_STATS_TEST=FAIL ",message); quit(1)

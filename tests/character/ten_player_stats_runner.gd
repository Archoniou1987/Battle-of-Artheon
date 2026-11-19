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
	var base := {"mana":30}
	var snapshots:Array[Dictionary] = []
	for bot in bots:
		var fighter := CharacterCombatBuilder.build(bot, repository, base)
		var snapshot := CharacterCombatBuilder.stats_snapshot(fighter)
		snapshot["equipment"] = _equipment_summary(bot, repository)
		snapshots.append(snapshot)
		print("PLAYER_STATS ", JSON.stringify(snapshot))
	var valid := true
	if all_items.size() != 60:
		_fail_condition("item_count", "ALL", {"expected":60, "actual":all_items.size()})
		valid = false
	if snapshots.size() != 10:
		_fail_condition("player_count", "ALL", {"expected":10, "actual":snapshots.size()})
		valid = false
	for snapshot in snapshots:
		if not _validate_snapshot(snapshot):
			valid = false
	print("TEN_PLAYER_STATS items=", all_items.size(), " players=", snapshots.size(), " entities_alive=", valid)
	print("TEN_PLAYER_STATS_TEST=", "PASS" if valid else "FAIL")
	quit(0 if valid else 1)

func _equipment_summary(bot:CharacterState, repository:ItemRepository)->Dictionary:
	var result:Dictionary={}
	for slot in ["head","chest","legs","feet","main_hand","off_hand"]:
		var item:=ItemResolver.resolve_equipped(slot, bot.equipment, repository)
		result[slot]={"instance_id":item.get("instance_id",""),"name":item.get("name",""),"level":item.get("item_level",0),"quality":item.get("quality","")}
	return result

func _validate_snapshot(snapshot:Dictionary)->bool:
	var valid := true
	var character_id := String(snapshot.get("character_id", "UNKNOWN"))
	var cs:Dictionary = snapshot.get("combat_stats", {})
	var eq:Dictionary = snapshot.get("equipment", {})
	var armour:Dictionary = snapshot.get("armour", {})
	if eq.size() != 6:
		_fail_condition("equipment_slot_count", character_id, {"expected":6, "actual":eq.size(), "equipment":eq})
		valid = false
	for slot in ["head","chest","legs","feet","main_hand","off_hand"]:
		var item:Dictionary = eq.get(slot, {})
		if String(item.get("instance_id", "")).is_empty():
			_fail_condition("equipment_slot_missing", character_id, {"slot":slot, "equipment":eq})
			valid = false
	if int(snapshot.get("max_hp", 0)) <= 100:
		_fail_condition("max_hp", character_id, {"expected_gt":100, "actual":snapshot.get("max_hp", 0), "max_hp_flat":cs.get("max_hp_flat", 0), "stats":snapshot.get("stats", {})})
		valid = false
	var weapon_profiles:Array = cs.get("weapon_profiles", [])
	if weapon_profiles.is_empty():
		_fail_condition("weapon_profiles", character_id, {"expected_non_empty":true, "actual":weapon_profiles, "weapon_attack_count":cs.get("weapon_attack_count", 0)})
		valid = false
	if float(cs.get("dodge_rating_percent", 0)) <= 0.0:
		_fail_condition("dodge", character_id, {"expected_gt":0, "actual":cs.get("dodge_rating_percent", 0), "combat_stats":cs})
		valid = false
	if float(cs.get("shield_auto_block_rating_percent", 0)) <= 0.0:
		_fail_condition("auto_block", character_id, {"expected_gt":0, "actual":cs.get("shield_auto_block_rating_percent", 0), "combat_stats":cs})
		valid = false
	if armour.is_empty():
		_fail_condition("armour", character_id, {"expected_non_empty":true, "actual":armour})
		valid = false
	return valid

func _fail_condition(condition:String, character_id:String, details:Dictionary)->void:
	print("TEN_PLAYER_STATS_FAIL condition=", condition, " character=", character_id, " details=", JSON.stringify(details))

func _fail(message:String)->void:
	print("TEN_PLAYER_STATS_TEST=FAIL ",message); quit(1)

extends SceneTree

## Run manually with Godot headless before enabling the CI gate.
## Confirms the shared v1.2 calculator creates real stable ITEMIDs for
## physical sword/dagger/axe/hammer archetypes without remapping PAR.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("PHYSICAL_V12_FAIL=",label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var archetypes := [
		"SWORD_DEF","SWORD_DODGE","SWORD_CRIT",
		"DAGGER_DEF","DAGGER_ATTACK","DAGGER_PEN",
		"AXE_DEF","AXE_ATTACK","AXE_SHIELD",
		"HAMMER_DEF","HAMMER_ATTACK"
	]
	var families := {"SWORD_":"sword","DAGGER_":"dagger","AXE_":"axe","HAMMER_":"hammer"}
	var seed_value := 20261104
	for archetype_id in archetypes:
		var item := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value)
		_check(not item.is_empty(),archetype_id+"_generated")
		if item.is_empty():
			continue
		_check(String(item.get("instance_id","")).begins_with("ITEMID"),archetype_id+"_id")
		_check(String(item.get("slot",""))=="main_hand",archetype_id+"_slot")
		_check(Array(item.get("abilities",[])).size()==(4 if archetype_id.begins_with("SWORD_") or archetype_id.begins_with("DAGGER_") else 0),archetype_id+"_runtime_abi_gate")
		for prefix in families:
			if archetype_id.begins_with(String(prefix)):
				_check(String(item.get("weapon_class",""))==String(families[prefix]),archetype_id+"_family")
		var again := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value)
		_check(not again.is_empty() and item.get("damage",{})==again.get("damage",{}),archetype_id+"_stable_roll")
		_check(item.get("instance_id","")!=again.get("instance_id",""),archetype_id+"_unique_itemid")
		seed_value += 1
	for archetype_id in ["DAGGER_DEF","DAGGER_ATTACK","DAGGER_PEN"]:
		var offhand := ItemV12InstanceFactory.generate_weapon(archetype_id,40,"purple",seed_value,"OH")
		_check(not offhand.is_empty(),archetype_id+"_offhand_generated")
		_check(String(offhand.get("slot",""))=="off_hand",archetype_id+"_offhand_slot")
		_check(Array(offhand.get("abilities",[])).is_empty(),archetype_id+"_offhand_no_duplicate_abi")
		seed_value += 1
	# Selecting a mass-generator result must not roll its CORE/PAR again.
	var engine := ItemTemplateGeneratorV12.new()
	var batch := engine.generate({"archetypes":["DAGGER_ATTACK"],"weapon_hand":"MH","min_level":40,"max_level":40,"quality":"purple","count":1,"seed":202611041,"group_qualities":false})
	_check(bool(batch.get("ok",false)),"mass_v12_generated")
	if bool(batch.get("ok",false)):
		var row: Dictionary = batch["rows"][0]
		var instance := ItemV12InstanceFactory.instance_from_v12_row(row,202611041)
		_check(not instance.is_empty(),"mass_row_converted")
		if not instance.is_empty():
			_check(Dictionary(instance.get("damage",{})).get("min",-1) == (row["variant"]["damage"] as Array)[0],"mass_damage_same")
			_check(instance.get("v12_core_rolls",[]) == row["variant"].get("core_rolls",[]),"mass_core_same")
			_check(instance.get("v12_rarity_rolls",[]) == row["variant"].get("rolls",[]),"mass_bonus_same")
	_check(ItemV12InstanceFactory.generate_weapon("AXE_DEF",40,"purple",1,"OH").is_empty(),"axe_no_oh")
	_check(ItemV12InstanceFactory.generate_weapon("HAMMER_MAGIC",40,"purple",1).is_empty(),"magic_not_implemented")
	print("PHYSICAL_WEAPON_V12_FACTORY=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)

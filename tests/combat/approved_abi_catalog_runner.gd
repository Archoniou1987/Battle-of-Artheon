extends SceneTree

## No temporary numbered ABI can re-enter production silently. The generic
## ABI test laboratory uses LAB_* IDs, not the production catalog.
func _initialize() -> void:
	var defs := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var ranges := [[301,308],[401,408],[501,508],[601,606]]
	var expected: Dictionary = {}
	for limits in ranges:
		for n in range(int(limits[0]),int(limits[1])+1):
			expected["ABI%d" % n] = true
	var ok := defs.size()==expected.size()
	for id in defs:
		ok = ok and expected.has(String(id))
		if not expected.has(String(id)):
			push_error("UNAPPROVED_ABI=" + String(id))
		else:
			var definition: Dictionary = defs[id]
			ok = ok and not definition.is_empty() and AbilityRuntime.validate_definition(String(id),definition).is_empty()
	for id in expected:
		ok = ok and defs.has(id)
	for retired in ["ABI001","ABI002","ABI003","ABI004","ABI005","ABI006","ABI300","ABI309","ABI400","ABI409","ABI500","ABI509","ABI600","ABI607","ABI700"]:
		ok = ok and not defs.has(retired) and AbilityCatalog.is_retired_numbered_abi(retired)
	for current in expected:
		ok = ok and not AbilityCatalog.is_retired_numbered_abi(String(current))
	var templates := ItemTemplateService.load_templates()
	ok = ok and not templates.has("training_fire_staff_abi003") and not templates.has("training_healer_chest_abi004")
	# Ordinary weapon attacks are not an undisclosed ABI001 cast.
	var basic := WeaponAttackProfile.attack_payload(
		{"id":"basic","damage_min":1.0,"damage_max":2.0,"damage_type":"slashing"},
		{"damage":0.5})
	ok = ok and String(basic.get("ability_id","")).is_empty()
	var bot_fixtures := TestFixtureLoader.load_json("res://data/test/bot_equipment_templates.json")
	for template in Array(bot_fixtures.get("templates",[])):
		for ability_id in Array(Dictionary(template).get("abilities",[])):
			ok = ok and not AbilityCatalog.is_retired_numbered_abi(String(ability_id))
	print("APPROVED_ABI_CATALOG_TEST=" + ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

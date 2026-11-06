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
	# Every approved ABI must retain its weapon-family dispatch mode, and
	# all referenced EFF definitions must exist before runtime application.
	var effect_defs := EffectCatalog.load_json()
	for id in expected:
		var approved: Dictionary = defs.get(id,{})
		var family_field := "sword_ability_mode"
		if String(id).begins_with("ABI4"):
			family_field = "dagger_ability_mode"
		elif String(id).begins_with("ABI5"):
			family_field = "axe_ability_mode"
		elif String(id).begins_with("ABI6"):
			family_field = "hammer_ability_mode"
		ok = ok and not String(approved.get(family_field,"")).is_empty()
		for effect_field in ["effect_id","sword_eff_id","eff"]:
			var effect_id := String(approved.get(effect_field,""))
			if not effect_id.is_empty():
				ok = ok and not EffectCatalog.definition(effect_defs,effect_id).is_empty()
		for component in Array(approved.get("components",[])):
			if component is Dictionary and String(component.get("kind","")) == "effect":
				var effect_id := String(component.get("effect_id",""))
				ok = ok and not effect_id.is_empty() and not EffectCatalog.definition(effect_defs,effect_id).is_empty()
	for retired in ["ABI001","ABI002","ABI003","ABI004","ABI005","ABI006","ABI300","ABI309","ABI400","ABI409","ABI500","ABI509","ABI600","ABI607","ABI700"]:
		ok = ok and not defs.has(retired) and AbilityCatalog.is_retired_numbered_abi(retired)
	for current in expected:
		ok = ok and not AbilityCatalog.is_retired_numbered_abi(String(current))
	# A forged catalog, legacy save/loadout, or noncanonical ABI alias must
	# never activate a retired numbered ability. Developer TEST_* IDs remain usable.
	var injected: Dictionary = defs.duplicate(true)
	injected["ABI001"] = Dictionary(defs["ABI301"]).duplicate(true)
	injected["ABI0301"] = Dictionary(defs["ABI301"]).duplicate(true)
	var saved_loadouts := {"CASTER":["ABI001","ABI0301","ABI301","TEST_ABI_FIREBALL"]}
	var active := AbilityCatalog.assigned_abilities(saved_loadouts,"CASTER")
	ok = ok and active == ["ABI301","TEST_ABI_FIREBALL"]
	ok = ok and saved_loadouts["CASTER"].size() == 4 # Persisted legacy IDs are not erased.
	ok = ok and AbilityCatalog.definition(injected,"ABI001").is_empty()
	ok = ok and AbilityCatalog.definition(injected,"ABI0301").is_empty()
	ok = ok and not AbilityCatalog.definition(injected,"ABI301").is_empty()
	ok = ok and not AbilityCatalog.is_executable_id("ABI_NOT_A_NUMBER")
	ok = ok and AbilityCatalog.is_executable_id("TEST_ABI_FIREBALL")
	var fixture_defs := AbilityCatalog.load_json("res://data/test/abilities.json")
	ok = ok and not AbilityCatalog.definition(fixture_defs,"TEST_ABI_FIREBALL").is_empty()
	var state := CombatState.new()
	state.round_number = 1
	var fighter := TestFixtureLoader.new_combatant("CASTER","Tester",10,1000,100)
	var target := TestFixtureLoader.new_combatant("TARGET","Target",10,1000,100)
	# Legacy and malformed IDs must also disappear from combat stat readouts,
	# without rewriting their original saved loadout.
	fighter.combat_stats["abilities"] = ["ABI001","ABI0301","ABI301","TEST_ABI_FIREBALL"]
	ok = ok and CombatModifierService.abilities(fighter) == ["ABI301","TEST_ABI_FIREBALL"]
	ok = ok and Array(fighter.combat_stats["abilities"]).size() == 4
	state.add_combatant(fighter)
	state.add_combatant(target)
	var old_only := AbilityScheduler.new(injected,{"CASTER":["ABI001","ABI0301"]})
	var mana_before := fighter.mana
	ok = ok and old_only.ready_events(state,"CASTER","TARGET").is_empty()
	ok = ok and old_only.cast_event(state,"CASTER","TARGET","ABI001") == null
	ok = ok and old_only.cast_event(state,"CASTER","TARGET","ABI0301") == null
	ok = ok and old_only.cast_zone_event(state,"CASTER",1,"ABI001") == null
	ok = ok and fighter.mana == mana_before and Dictionary(old_only.cooldowns_by_combatant.get("CASTER",{})).is_empty() and old_only.cast_round_by_combatant.is_empty()
	var group := GroupCombatState.new(state)
	group.add_member("A","CASTER")
	group.add_member("B","TARGET")
	group.set_active_opponent("CASTER","TARGET")
	group.set_active_opponent("TARGET","CASTER")
	var zones := CombatZoneState.new(group)
	var orchestrator := RoundOrchestrator.new(state,CombatEngine.new(state),group,zones)
	var command := CombatCommandApi.new(state,group,zones,orchestrator,old_only)
	var actions := command.available_actions("CASTER",{"ABI001":injected["ABI001"],"ABI0301":injected["ABI0301"],"ABI301":injected["ABI301"]})
	var shown: Dictionary = actions.get("abilities",{})
	ok = ok and not shown.has("ABI001") and not shown.has("ABI0301") and shown.has("ABI301")
	ok = ok and not bool(command.cast_ability("CASTER","TARGET","ABI001").get("ok",false))
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

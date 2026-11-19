extends SceneTree

## Approved fire ABI IDs, effect ownership, SP scaling and level bands.
## Does not imply the v1.2 staff instance is live.
func _initialize() -> void:
	var defs := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var expected := ["ABI801","ABI802","ABI803","ABI804"]
	var valid := true
	for id in expected:
		var d: Dictionary = defs.get(id,{})
		valid = valid and AbilityCatalog.is_executable_id(id)
		var definition_errors := AbilityRuntime.validate_definition(id,d)
		if not definition_errors.is_empty():
			print("FIRE_ABI_DEF_ERRORS id=",id," errors=",JSON.stringify(definition_errors))
		valid = valid and definition_errors.is_empty()
		valid = valid and String(d.get("magic_school",""))=="fire"
		valid = valid and String(d.get("magic_archetype",""))=="STAFF_FIRE_BURST"
		valid = valid and Array(d.get("base_damage_by_rank",[])).size()==10
		valid = valid and String(d.get("application_timing",""))=="standard"
		for component in Array(d.get("components",[])):
			if String(component.get("kind",""))=="damage":
				valid = valid and String(component.get("damage_type",""))=="fire"
				valid = valid and float(component.get("spell_power_scale",-1)) > 0.0
		valid = valid and (AbilityRuntime.extra_cast_eligible(d) == (id=="ABI802"))
	print("FIRE_EFFECT_REF=",AbilityCatalog.effect_id("ABI801"))
	valid = valid and AbilityCatalog.effect_id("ABI801")=="EFF003"
	valid = valid and AbilityCatalog.ranked_damage("ABI801",40)==155.0
	valid = valid and AbilityCatalog.ranked_damage("ABI802",40)==90.0
	valid = valid and AbilityCatalog.ranked_damage("ABI803",40)==175.0
	valid = valid and AbilityCatalog.ranked_damage("ABI804",40)==300.0
	var state := CombatState.new()
	var caster := TestFixtureLoader.new_combatant("caster","Caster",40,1000,500)
	caster.combat_stats["par_totals"]["PAR150"]=100.0
	caster.combat_stats["magic_damage_rating"]=100.0 # Legacy fixture mirror used by PAR canonicalization
	var target := TestFixtureLoader.new_combatant("target","Target",40,10000,0)
	state.add_combatant(caster)
	state.add_combatant(target)
	var engine := CombatEngine.new(TestFixtureLoader.canonicalize_state(state))
	for id in expected:
		var spell: Dictionary=defs[id]
		var parent := AbilityRuntime.build_action_event(state,"caster","target",id,spell)
		var components: Array=spell.get("components",[])
		var damage: Dictionary={}
		for component in components:
			if String(component.get("kind",""))=="damage":
				damage=component
		var hit := engine._make_action_component_event(parent,damage,"target",1.0)
		var raw := float(damage.get("amount",0.0))+100.0*float(damage.get("spell_power_scale",0.0))
		if not is_equal_approx(float(hit.payload.get("amount",-1.0)),raw):
			print("FIRE_ABI_DAMAGE_MISMATCH id=",id," expected=",raw," actual=",hit.payload.get("amount",-1.0))
		valid = valid and is_equal_approx(float(hit.payload.get("amount",-1.0)),raw)
	# Verify rank comes from the equipped staff level, not character level.
	caster.combat_stats["weapon_profiles"]=[{"weapon_class":"staff","item_level":20,"damage_min":1,"damage_max":1}]
	var rank20 := AbilityRuntime.build_action_event(state,"caster","target","ABI801",defs["ABI801"])
	valid = valid and is_equal_approx(float(Dictionary(rank20.payload.get("components",[])[0]).get("amount",-1.0)),39.0)
	caster.combat_stats["weapon_profiles"]=[{"weapon_class":"staff","item_level":75,"damage_min":1,"damage_max":1}]
	var rank75 := AbilityRuntime.build_action_event(state,"caster","target","ABI801",defs["ABI801"])
	valid = valid and is_equal_approx(float(Dictionary(rank75.payload.get("components",[])[0]).get("amount",-1.0)),344.0)
	valid = valid and is_equal_approx(float(Dictionary(defs["ABI801"]["components"][0]).get("amount",-1)),155.0)
	print("FIRE_BURST_ABI_CONTRACT=" + ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

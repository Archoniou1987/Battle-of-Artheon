extends SceneTree

## Deterministic cross-weapon integration: use the production CombatEngine,
## canonical PAR fixtures, real EFF catalog and the common event queue.
## No artificial damage modifiers or alternate attack resolution.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ABI_CROSS_WEAPON_CASE=FAIL ",label)

func _initialize() -> void:
	_legacy_design_is_non_runtime()
	_abi_to_eff_references()
	_char_npc_par_projection_contract()
	_npc_resource_and_level_ownership()

	_abi_target_limits_from_catalog()
	_legacy_abi_target_cap_fallback()
	_sword_cripple_versus_axe_damage()
	_sword_effect_strength_from_catalog()
	_eff_periodic_armour_policy_ownership()
	_eff_sword_scaling_ownership()
	_sword_hit_ap_and_critical_numbers_from_catalog()


	_item_weapon_on_hit_target_ownership()


	_mace_abi_cross_integration()
	_axe_wounds_from_eff()
	_axe_abi_coefficients_from_catalog()


	_axe_shield_breaker_catalog()

	print("ABI_CROSS_WEAPON_INTERACTION_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

## NPC keeps its explicitly authored PAR totals (no guessed primary
## derivation), but uses CHAR's same PAR source_key projection and RatingMatrix.
## Test-only values are deliberately different from production NPC data.
func _char_npc_par_projection_contract() -> void:
	var document: Dictionary = TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var npc_fixture: Dictionary = Dictionary(Array(document.get("npcs",[]))[2]).duplicate(true)
	var base: Dictionary = npc_fixture["base"]
	var totals: Dictionary = base["par_totals"]
	totals["PAR015"] = 2.0
	totals["PAR053"] = 6.0
	totals["PAR071"] = 4.0
	totals["PAR125"] = 11.0
	totals["PAR126"] = 0.12
	totals["PAR135"] = 7.0
	base["combat_stats"]["shield_auto_block_direct_pct"] = 2.0
	var npc := NpcState.new(npc_fixture)
	var fighter := NpcCombatBuilder.build(npc)
	_check(fighter != null,"A07:NPC_explicit_PAR_build_valid")
	if fighter != null:
		_check(fighter.max_hp==75 and fighter.max_mana==0,"A07:explicit_NPC_resource_pools_unchanged")
		_check(is_equal_approx(float(fighter.combat_stats.get("mana_regen_round",-1)),2.0),"A07:NPC_PAR015_source_key")
		_check(is_equal_approx(float(fighter.combat_stats.get("physical_damage_piercing_pct",-1)),6.0),"A07:NPC_PAR053_source_key")
		_check(is_equal_approx(float(fighter.combat_stats.get("damage_reduction_pct",-1)),7.0),"A07:NPC_PAR135_source_key")
		_check(is_equal_approx(float(fighter.combat_stats.get("shield_auto_block_direct_pct",-1)),6.0),"A07:NPC_PAR071_plus_existing_overlay")
		_check(is_equal_approx(float(fighter.combat_stats.get("armour_penetration_flat",-1)),11.0),"A07:NPC_PAR125_alias_unchanged")
		_check(is_equal_approx(float(fighter.combat_stats.get("armour_penetration_percent",-1)),0.12),"A07:NPC_PAR126_alias_unchanged")
		_check(is_equal_approx(float(fighter.combat_stats.get("hit_chance_rating",-1)),0.0),"A07:NPC_no_unapproved_primary_derived_rating")
		_check(is_equal_approx(float(fighter.combat_stats.get("hit_chance_rating_percent",-1)),RatingMatrix.to_percent(0.0,npc.level)),"A07:NPC_uses_existing_RatingMatrix")
	var expected_source_keys := CharacterStatsService.par_source_fields(totals,[
		"PAR015","PAR016","PAR053","PAR054","PAR055","PAR056","PAR071","PAR072","PAR135"
	])
	_check(is_equal_approx(float(expected_source_keys.get("shield_auto_block",-1)),4.0),"A07:source_key_projection_uses_registry")
	_check(is_equal_approx(float(expected_source_keys.get("mana_regen_round",-1)),2.0),"A07:source_key_projection_keeps_PAR015")

	var hero := CharacterState.new("a07_projection_character","Projection Test",5)
	var repo := ItemRepository.new()
	var par := ParCalculationService.calculate(hero,repo)
	var hero_snapshot := CharacterStatsService.snapshot(hero,repo,{},par)
	_check(not hero_snapshot.is_empty(),"A07:CHAR_snapshot_available")
	var char_fields := CharacterStatsService.par_source_fields(Dictionary(par.get("totals",{})))
	for key in char_fields:
		# PAR050/PAR051 are attack-range owners; their UI snapshot keys
		# intentionally become [min,max] arrays (or are absent without OH).
		# Compare only scalar PAR source fields here, never Array == float.
		if key == "main_hand_damage" or key == "off_hand_damage":
			continue
		var mapped: Variant = hero_snapshot.get(key,null)
		var raw: Variant = char_fields[key]
		_check(RatingMatrix._number(mapped) and RatingMatrix._number(raw) and is_equal_approx(float(mapped),float(raw)),"A07:CHAR_scalar_projection_"+String(key))
	var main_damage: Variant = hero_snapshot.get("main_hand_damage",null)
	_check(main_damage is Array and Array(main_damage).size()==2,"A07:CHAR_main_hand_range_is_array")
	_check(not hero_snapshot.has("off_hand_damage"),"A07:CHAR_absent_off_hand_has_no_range")


## A07 resource/level contract: the world uses NPC template pools
## when supplied. Legacy fallback remains for incomplete old templates,
## while combat_level changes RatingMatrix conversion, not authored strength.
## This is an audit guard, not approval of NPC balance/scaling.
func _npc_resource_and_level_ownership() -> void:
	var document: Dictionary = TestFixtureLoader.load_json("res://data/npc/starting_region_npcs.json")
	var chief_data: Dictionary = Dictionary(Array(document.get("npcs",[]))[4]).duplicate(true)
	var base: Dictionary = chief_data["base"]
	var totals: Dictionary = base["par_totals"]
	totals["PAR031"] = 100.0
	var npc := NpcState.new(chief_data)
	var original := NpcCombatBuilder.build(npc)
	_check(original != null,"A07:authored_NPC_resources_build")
	if original == null:
		return
	_check(original.max_hp==140 and original.max_mana==20,"A07:authored_HP_mana_override_legacy_fallback")
	_check(is_equal_approx(float(original.combat_stats.get("dodge_rating_percent",-1)),RatingMatrix.to_percent(100.0,npc.level)),"A07:NPC_rating_uses_own_level")
	var scaled_level := NpcCombatBuilder.build(npc,60)
	_check(scaled_level != null,"A07:combat_level_override_build")
	if scaled_level != null:
		_check(scaled_level.level==60,"A07:combat_level_sets_runtime_level")
		_check(scaled_level.max_hp==140 and scaled_level.max_mana==20,"A07:combat_level_does_not_silently_scale_resources")
		_check(scaled_level.combat_stats["par_totals"]==original.combat_stats["par_totals"],"A07:combat_level_keeps_authored_PAR")
		_check(is_equal_approx(float(scaled_level.combat_stats.get("dodge_rating_percent",-1)),RatingMatrix.to_percent(100.0,60)),"A07:combat_level_uses_canonical_rating_curve")
	# Absent pools use the OLD NPC fallback. This differs from CHAR
	# max-mana derivation and must not be changed without balance approval.
	var legacy_data: Dictionary = chief_data.duplicate(true)
	var legacy_base: Dictionary = legacy_data["base"]
	legacy_base.erase("health")
	legacy_base.erase("mana")
	var legacy := NpcCombatBuilder.build(NpcState.new(legacy_data))
	_check(legacy != null,"A07:legacy_NPC_missing_resource_pools_build")
	if legacy != null:
		_check(legacy.max_hp==190 and legacy.max_mana==60,"A07:legacy_NPC_fallback_unchanged")
	var char_pools := CharacterState.maximum_resources({"PAR010":90,"PAR011":40})
	_check(int(char_pools["max_hp"])==190 and int(char_pools["max_mana"])==70,"A07:CHAR_canonical_resource_formula_distinct_from_legacy_NPC")
	# No coefficient for an elite rank or for 75->100% PvE levelling is
	# applied by this builder today. Rank remains authored metadata.
	_check(String(npc.rank)=="elite" and scaled_level != null and scaled_level.max_hp==original.max_hp,"A07:rank_does_not_implicitly_change_HP")

## A08: The November design JSON is an archive, never an ABI/EFF
## numeric source. Do NOT test equality with historical balance numbers.
func _legacy_design_is_non_runtime() -> void:
	const DESIGN_PATH := "res://data/abilities/physical_onehand_v12_design.json"
	var historic: Dictionary = TestFixtureLoader.load_json(DESIGN_PATH)
	_check(String(historic.get("runtime_status",""))=="historical_design_only","A08:design_marked_historical")
	_check(historic.get("runtime_authoritative",true)==false,"A08:design_not_runtime_authority")
	_check(Array(historic.get("canonical_runtime_sources",[]))==[
		AbilityCatalog.CANONICAL_PATH,EffectCatalog.DEFAULT_PATH
	],"A08:single_authoritative_ABI_EFF_catalog_paths")
	_check(AbilityCatalog.CANONICAL_PATH!=DESIGN_PATH and EffectCatalog.DEFAULT_PATH!=DESIGN_PATH,"A08:runtime_loaders_do_not_target_design")
	var runtime_abi: Dictionary = AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var runtime_eff: Dictionary = EffectCatalog.load_json()
	_check(runtime_abi.has("ABI404") and runtime_eff.has("EFF406"),"A08:runtime_catalogs_own_approved_ABI_EFF")
	_check(not historic.has("ABI404") and historic.has("abilities"),"A08:design_has_historical_structure_only")


func _abi_to_eff_references() -> void:
	var abilities := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	for abi_id in abilities:
		var abi: Dictionary = abilities[abi_id]
		_check(not abi.has("eff") and not abi.has("effect_level"),String(abi_id)+":no_duplicate_eff_aliases")
		var primary := AbilityCatalog.effect_id(String(abi_id))
		for raw in abi.get("components", []):
			if raw is Dictionary and String(raw.get("kind", "")) == "effect":
				var expected := String(raw.get("effect_id", ""))
				_check(primary == expected and effects.has(expected), String(abi_id) + ":primary_eff_reference")
		if abi.has("sword_eff_id"):
			_check(primary == String(abi["sword_eff_id"]) and effects.has(primary), String(abi_id) + ":sword_eff_reference")
		var roles: Dictionary = abi.get("effect_refs", {})
		for role in roles:
			var expected := String(roles[role])
			_check(AbilityCatalog.effect_id(String(abi_id),String(role)) == expected and effects.has(expected), String(abi_id) + ":" + String(role) + "_eff_reference")

## ABI owns target caps, including unscheduled/custom action snapshots.
func _abi_target_limits_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	for spec in [
		{"abi":"ABI307","class":"sword","expected":3},
		{"abi":"ABI308","class":"sword","expected":5},
		{"abi":"ABI407","class":"dagger","expected":5},
		{"abi":"ABI503","class":"axe","expected":3}
	]:
		var id := String(spec["abi"])
		var authored: Dictionary = defs.get(id,{})
		_check(int(authored.get("max_targets",-1)) == int(spec["expected"]),id+":canonical_target_cap")
		var ctx := _pair(String(spec["class"]),"hammer")
		var state: CombatState = ctx["state"]
		var action_definition: Dictionary = authored.duplicate(true)
		var intent := AbilityRuntime.build_action_event(state,"left","right",id,action_definition)
		_check(int(intent.payload.get("max_targets",-1)) == int(spec["expected"]),id+":target_cap_in_event")
		if id == "ABI308":
			continue
		# Lower cap in a test-only event, with more than two valid enemies.
		action_definition["max_targets"] = 2
		state.add_combatant(_fighter("extra_1","hammer"))
		state.add_combatant(_fighter("extra_2","hammer"))
		var limited := AbilityRuntime.build_action_event(state,"left","right",id,action_definition)
		var engine: CombatEngine = ctx["engine"]
		if id == "ABI307":
			SwordAbiCombatService.dispatch(engine,limited)
		elif id == "ABI407":
			WeaponComboAbiCombatService.dispatch(engine,limited)
		else:
			AxeAbiCombatService.dispatch(engine,limited)
		_check(Array(limited.result.get("child_event_ids",[])).size() == 2,id+":target_cap_dispatch")

## Queued combat ACTIONs from before the max_targets field existed
## must retain the authored AoE size, not silently fall back to one target.
func _legacy_abi_target_cap_fallback() -> void:
	for spec in [
		{"abi":"ABI307","class":"sword","mode":"dodge_aoe","count":3},
		{"abi":"ABI308","class":"sword","mode":"dodge_e","count":5},
		{"abi":"ABI407","class":"dagger","mode":"","count":5},
		{"abi":"ABI503","class":"axe","mode":"","count":3}
	]:
		var ctx := _pair(String(spec["class"]),"hammer")
		var state: CombatState = ctx["state"]
		var engine: CombatEngine = ctx["engine"]
		for i in range(4):
			state.add_combatant(_fighter("legacy_extra_"+str(i),"hammer"))
		var id := String(spec["abi"])
		var action := state.create_event(CombatEvent.Kind.ACTION,"left","right",{
			"ability_id":id,"source_kind":"ability","zone":"chest",
			"sword_ability_mode":String(spec["mode"]),"ap_spent":1
		})
		if String(spec["class"]) == "sword":
			SwordAbiCombatService.dispatch(engine,action)
		elif String(spec["class"]) == "dagger":
			WeaponComboAbiCombatService.dispatch(engine,action)
		else:
			AxeAbiCombatService.dispatch(engine,action)
		_check(Array(action.result.get("child_event_ids",[])).size()==int(spec["count"]),id+":legacy_target_cap_from_catalog")


## Changed test-only ABI601 bonuses must reach the first ordinary
## MH attack and real CombatEngine damage without any repeated +20 constant.
func _sword_hit_ap_and_critical_numbers_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var actor := state.get_combatant("left")
	var q := AbilityRuntime.build_action_event(state,"left","right","ABI301",defs["ABI301"])
	q.payload["zone"] = "chest"
	SwordAbiCombatService.dispatch(engine,q)
	var shots := Array(q.result.get("child_event_ids",[]))
	_check(shots.size()==1,"ABI301:one_new_numeric_attack")
	var profile: Dictionary = WeaponAttackProfile.all(actor)[0]
	_check(is_equal_approx(AbilityCatalog.ranked_damage("ABI301",int(profile.get("item_level",1))),12.0),"ABI301:ranked_base_damage")
	var effects := EffectCatalog.load_json()
	_check(int(Dictionary(effects["EFF314"]).get("max_stacks",0))==3,"SWORD:mastery_owned_by_EFF")
	var crit_ctx := _pair("sword","axe")
	var crit_action := AbilityRuntime.build_action_event(crit_ctx["state"],"left","right","ABI312",defs["ABI312"])
	crit_action.payload["zone"]="chest"
	SwordAbiCombatService.dispatch(crit_ctx["engine"],crit_action)
	var found := false
	for pending in crit_ctx["state"].pending_events:
		if pending.kind == CombatEvent.Kind.ATTACK and String(pending.payload.get("sword_abi_id",""))=="ABI312":
			found = is_equal_approx(float(pending.payload.get("sword_crit_chance_pct",0.0)),40.0)
	_check(found,"ABI312:approved_plus40_crit_points")

func _axe_abi_coefficients_from_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	for n in range(501,517):
		var id := "ABI%d" % n
		_check(defs.has(id),id+":in_canonical_catalog")
		_check(Array(Dictionary(defs[id]).get("base_damage_by_rank",[])).size()==10,id+":ten_damage_ranks")
		_check(not Dictionary(defs[id]).has("mh_damage_bonus_pct"),id+":no_retired_mh_multiplier")
	var wounds: Dictionary = effects["EFF501"]
	_check(int(wounds.get("max_stacks",0))==3,"axe:wounds_max3")
	_check(int(wounds.get("duration_rounds",0))==5,"axe:wounds_five_rounds")
	_check(Array(Dictionary(wounds.get("values_by_rank",{})).get("damage",[])).size()==10,"axe:dot_ten_ranks")
	var expected_heal := [0.0,15.0,40.0,75.0]
	var heal: Array = Dictionary(defs["ABI504"]).get("heal_from_damage_pct_by_wounds",[])
	var heal_matches := heal.size()==expected_heal.size()
	if heal_matches:
		for i in range(heal.size()):
			heal_matches = heal_matches and is_equal_approx(float(heal[i]),expected_heal[i])
	_check(heal_matches,"ABI504:heal_pct_by_wounds")
	var expected_execute := [0.0,75.0,100.0,125.0]
	var execute: Array = Dictionary(defs["ABI508"]).get("bonus_damage_pct_by_wounds",[])
	var execute_matches := execute.size()==expected_execute.size()
	if execute_matches:
		for i in range(execute.size()):
			execute_matches = execute_matches and is_equal_approx(float(execute[i]),expected_execute[i])
	_check(execute_matches,"ABI508:execute_bonus")
	_check(is_equal_approx(float(Dictionary(defs["ABI508"]).get("execute_hp_threshold_fraction",0)),0.35),"ABI508:execute_threshold")
	_check(int(Dictionary(defs["ABI512"]).get("max_targets",0))==1,"ABI512:one_target")
	_check(bool(Dictionary(defs["ABI512"]).get("ignore_shield_auto_block",false)),"ABI512:shield_auto_bypass")
	_check(int(Dictionary(defs["ABI516"]).get("max_targets",0))==5,"ABI516:five_targets")
	var ctx := _pair("axe","dagger")
	var state: CombatState = ctx["state"]
	var target := state.get_combatant("right")
	_effect(ctx,"left","right","EFF501",{"sword_stacks_to_apply":2,"effect_rank":4},true)
	_check(AxeAbiCombatService._wounds(target,"left",state.round_number)==2,"axe:wounds_owned_by_source")
	_check(AxeAbiCombatService._wounds(target,"other",state.round_number)==0,"axe:wounds_other_source_not_counted")
	AxeAbiCombatService._consume_wounds(target,"left",1)
	_check(AxeAbiCombatService._wounds(target,"left",state.round_number)==1,"axe:wounds_partially_consumed")
func _item_weapon_on_hit_target_ownership() -> void:
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var actor := state.get_combatant("left")
	var defender := state.get_combatant("right")
	engine.canonical_effects["EFF003"]["on_hit_target"] = "enemy"
	actor.combat_stats["weapon_on_hit_effects"] = [
		{"effect_id":"EFF003","chance":100.0,"weapon_index":0},
		{"effect_id":"EFF005","chance":100.0,"weapon_index":0}
	]
	var hit := _attack(ctx,"left","right")
	_check(String(hit.result.get("outcome",""))=="connected","item:on_hit_fixture_connected")
	_check(not _active_effect(defender,"EFF003").is_empty(),"item:on_hit_enemy_from_EFF_definition")
	_check(_active_effect(actor,"EFF003").is_empty(),"item:enemy_dot_never_on_self")
	_check(not _active_effect(actor,"EFF005").is_empty(),"item:on_hit_default_self_target")
	var override_ctx := _pair("sword","axe")
	var override_state: CombatState = override_ctx["state"]
	var override_actor := override_state.get_combatant("left")
	override_actor.combat_stats["weapon_on_hit_effects"] = [
		{"effect_id":"EFF005","chance":100.0,"weapon_index":0,"target":"enemy"}
	]
	var override_hit := _attack(override_ctx,"left","right")
	_check(String(override_hit.result.get("outcome",""))=="connected","item:on_hit_override_fixture_connected")
	_check(not _active_effect(override_state.get_combatant("right"),"EFF005").is_empty(),"item:on_hit_trigger_explicit_enemy_target")
	_check(_active_effect(override_actor,"EFF005").is_empty(),"item:on_hit_trigger_override_not_self")


## The physical DoT armour calculation remains COMBAT's original
## calculation. Which EFF invokes it, with which zone/type, belongs to EFF.
func _eff_periodic_armour_policy_ownership() -> void:
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var source := state.get_combatant("left")
	var victim := state.get_combatant("right")
	victim.armour["chest"] = {"slashing":0.0}
	victim.armour["head"] = {"slashing":300.0}
	var base_damage := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF003"
	})
	engine.resolve_event(base_damage)
	var baseline := int(base_damage.result.get("final_damage",0))
	_check(baseline > 0,"EFF:baseline_physical_dot_positive")
	# An EFF301 event from a saved, pre-migration queue has no policy field.
	# It must still use the legacy chest/slashing rule from the EFF catalog.
	var legacy := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF301"
	})
	engine.resolve_event(legacy)
	_check(int(legacy.result.get("final_damage",-1))==baseline,"EFF301:legacy_no_policy_uses_canonical_chest")
	# Explicit event snapshots beat the current catalog, and a different
	# named EFF can use the same ordinary COMBAT formula.
	var policy := {"zone":"head","damage_type":"slashing","apply_source_physical_outgoing":true}
	var another_eff := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF003","periodic_armour":policy
	})
	engine.resolve_event(another_eff)
	_check(int(another_eff.result.get("final_damage",-1)) < baseline,"EFF003:policy_applies_without_EFF301_ID")
	var snapshot := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF301","periodic_armour":policy
	})
	engine.resolve_event(snapshot)
	_check(int(snapshot.result.get("final_damage",-1))==int(another_eff.result.get("final_damage",-2)),"EFF301:event_snapshot_overrides_catalog")
	# Test-only physical outgoing bonus applies ONLY when requested by EFF.
	source.active_effects.append({
		"effect_id":"TEST_OUTGOING_BONUS","definition":{"physical_damage_outgoing_direct_pct":50.0},
		"source_id":"left","start_round":1,"remaining_rounds":2
	})
	var boosted := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF301","periodic_armour":{}
	})
	engine.resolve_event(boosted)
	_check(int(boosted.result.get("final_damage",-1))==baseline,"EFF301:empty_snapshot_disables_periodic_armour_policy")
	var outgoing := state.create_event(CombatEvent.Kind.DAMAGE,"left","right",{
		"amount":100.0,"damage_type":"physical","source":"effect","effect_id":"EFF301","periodic_armour":{"zone":"chest","damage_type":"slashing","apply_source_physical_outgoing":true}
	})
	engine.resolve_event(outgoing)
	_check(int(outgoing.result.get("final_damage",-1)) > baseline,"EFF301:source_outgoing_modifier_follows_policy")

	# The real periodic phase must copy the *applied* EFF snapshot to DAMAGE
	# rather than rereading new values from the catalog.
	var timed_ctx := _pair("sword","axe")
	var timed_state: CombatState = timed_ctx["state"]
	var timed_engine: CombatEngine = timed_ctx["engine"]
	var timed_victim := timed_state.get_combatant("right")
	var timed_def: Dictionary = EffectCatalog.definition(timed_engine.canonical_effects,"EFF301").duplicate(true)
	timed_def["periodic_armour"]["zone"] = "head"
	timed_victim.active_effects.append({
		"effect_id":"EFF301","definition":timed_def,"source_id":"left",
		"start_round":1,"remaining_rounds":5,"stacks":2,"active_stacks":2
	})
	var orchestrator := RoundOrchestrator.new(timed_state,timed_engine)
	orchestrator.resolve_active_timed_effects()
	var saw_tick := false
	for event in timed_state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and String(event.payload.get("effect_id","")) == "EFF301" and String(event.payload.get("source","")) == "effect":
			saw_tick = true
			_check(String(Dictionary(event.payload.get("periodic_armour",{})).get("zone",""))=="head","EFF301:timed_tick_uses_applied_EFF_snapshot")
	_check(saw_tick,"EFF301:timed_tick_generated")

	# Retired ABI308 burst-tick behavior is no longer part of sword combat.


func _damage_type(weapon_class: String) -> String:
	match weapon_class:
		"sword": return "slashing"
		"dagger": return "piercing"
		"axe": return "chopping"
		_: return "blunt"

func _fighter(id: String, weapon_class: String) -> CombatantState:
	var fighter := TestFixtureLoader.new_combatant(id,id,10,10000,200)
	var weapon: Dictionary = {
		"slot":"main_hand","instance_id":id+"_mh","weapon_class":weapon_class,
		"damage_min":100.0,"damage_max":100.0,"damage_type":_damage_type(weapon_class)
	}
	var profiles: Array = [weapon]
	if weapon_class == "dagger":
		profiles.append({
			"slot":"off_hand","instance_id":id+"_oh","weapon_class":"dagger",
			"damage_min":75.0,"damage_max":75.0,"damage_type":"piercing"
		})
	TestFixtureLoader.set_weapon_profiles(fighter,profiles)
	fighter.combat_loadout["weapon_class"] = weapon_class
	fighter.combat_stats["manual_block_zones"] = []
	fighter.combat_stats["dodge_rating_percent"] = 0.0
	fighter.combat_stats["shield_auto_block_rating_percent"] = 0.0
	CombatTempoService.initialize(fighter,0.0,100.0,0.0)
	return fighter

func _pair(left_class: String, right_class: String) -> Dictionary:
	var state := CombatState.new()
	state.add_combatant(_fighter("left",left_class))
	state.add_combatant(_fighter("right",right_class))
	state.begin_round()
	var engine := CombatEngine.new(state)
	engine.combat_rng.seed = 20261106
	return {"state":state,"engine":engine}

func _effect(ctx: Dictionary, source_id: String, target_id: String, effect_id: String, extra: Dictionary = {}, instant: bool = false) -> CombatEvent:
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var payload: Dictionary = {
		"effect_id":effect_id, "source_type":"ability", "base_chance":100.0,
		"effect_roll":1, "preparation_effect":instant
	}
	for key in extra:
		payload[key] = extra[key]
	var event := state.create_event(CombatEvent.Kind.EFFECT,source_id,target_id,payload)
	engine.resolve_event(event)
	_check(bool(event.result.get("resolved",false)),effect_id+":resolved")
	return event

func _attack(ctx: Dictionary, source_id: String, target_id: String, index: int = 0, extra: Dictionary = {}, hit_roll: int = 1, dodge_roll: int = 100) -> CombatEvent:
	var state: CombatState = ctx["state"]
	var engine: CombatEngine = ctx["engine"]
	var source := state.get_combatant(source_id)
	var profiles := WeaponAttackProfile.all(source)
	var profile: Dictionary = profiles[index]
	var rolls := {
		"hit":hit_roll,"reaction":100,"dodge":dodge_roll,"auto_block":100,
		"block_crush":100,"crit":100,"on_hit_effect":100,"damage":0.5
	}
	var payload := WeaponAttackProfile.attack_payload(profile,rolls,"chest")
	for key in extra:
		payload[key] = extra[key]
	var event := state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,payload)
	state.queue_event(event)
	engine.resolve_pending_events()
	return event

func _effects_count(fighter: CombatantState, effect_id: String) -> int:
	var n := 0
	for raw in fighter.active_effects:
		if String(Dictionary(raw).get("effect_id","")) == effect_id:
			n += 1
	return n

func _effect_stacks(fighter: CombatantState, effect_id: String) -> int:
	var n := 0
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			n += int(record.get("stacks",0))
	return n

func _sword_cripple_versus_axe_damage() -> void:
	var ctx := _pair("sword","axe")
	var state: CombatState = ctx["state"]
	var axe := state.get_combatant("right")
	var weaken := _effect(ctx,"left","right","EFF320")
	_check(bool(weaken.result.get("resolved",false)),"sword:E320_weakening_applied")
	state.begin_round()
	_check(is_equal_approx(CombatModifierService.modifier(axe,"physical_damage_outgoing_direct_pct",state.round_number),-15.0),"sword:unique_weaken_reduces_axe_by15")
	var hit := _attack(ctx,"right","left")
	_check(String(hit.result.get("outcome",""))=="connected","sword:axe_hit_connected")
	_check(is_equal_approx(float(hit.result.get("raw_damage",-1.0)),85.0),"sword:weakening_applies_to_axe")

func _sword_effect_strength_from_catalog() -> void:
	var defs := EffectCatalog.load_json()
	var mastery: Dictionary = defs["EFF314"]
	_check(int(mastery.get("max_stacks",0))==3,"EFF314:mastery_max3")
	_check(int(mastery.get("duration_rounds",0))==3,"EFF314:mastery_three_rounds")
	_check(is_equal_approx(float(mastery.get("hit_chance_direct_pct",0.0)),3.0),"EFF314:hit_bonus_from_catalog")
	_check(is_equal_approx(float(mastery.get("damage_reduction",0.0)),0.02),"EFF314:resistance_from_catalog")
	var fury: Dictionary = defs["EFF318"]
	_check(is_equal_approx(float(fury.get("crit_chance_direct_pct",0.0)),20.0),"EFF318:blind_fury_crit")
	_check(is_equal_approx(float(fury.get("incoming_damage_direct_pct",0.0)),15.0),"EFF318:blind_fury_vulnerability")

func _eff_sword_scaling_ownership() -> void:
	var defs := EffectCatalog.load_json()
	for id in ["EFF319","EFF321"]:
		var definition: Dictionary = defs[id]
		var ranked: Array = definition.get("rating_delta_by_rank",[])
		_check(ranked.size()==10,id+":has_ten_effect_ranks")
		if ranked.size()==10:
			var third := EffectCatalog.application_modifiers(definition,{"effect_rank":3})
			var key := "anti_crit_rating_delta" if id=="EFF319" else "hit_chance_rating_delta"
			_check(is_equal_approx(float(third.get(key,0)),float(ranked[2])),id+":rank_magnitude_from_EFF")
	var rank_1 := AbilityCatalog.rank_for_item_level(1)
	var rank_75 := AbilityCatalog.rank_for_item_level(75)
	_check(rank_1==0 and rank_75==7,"ABI:ten_level_rank_boundaries")

func _active_effect(fighter: CombatantState, effect_id: String) -> Dictionary:
	for raw in fighter.active_effects:
		var record: Dictionary = raw
		if String(record.get("effect_id","")) == effect_id:
			return record
	return {}


func _axe_wounds_from_eff() -> void:
	var ctx := _pair("axe","dagger")
	var state: CombatState = ctx["state"]
	var target := state.get_combatant("right")
	_effect(ctx,"left","right","EFF501",{"sword_stacks_to_apply":3,"effect_rank":4},true)
	_check(AxeAbiCombatService._wounds(target,"left",state.round_number)==3,"axe:wounds_applied")
	var resolved := _active_effect(target,"EFF501")
	_check(int(Dictionary(resolved.get("definition",{})).get("effect_rank",0))==4,"axe:wound_effect_rank_from_EFF")
func _axe_shield_breaker_catalog() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effects := EffectCatalog.load_json()
	_check(not defs.has("ABI517"),"axe:reject_unapproved_517")
	_check(not effects.has("EFF505"),"axe:retired_crusher_effect_removed")
	_check(int(Dictionary(defs["ABI510"]).get("block_crush_bonus_pct",0))==40,"axe:shieldbreaker_plus40_block_crush")
	_check(int(Dictionary(defs["ABI511"]).get("shield_damage_bonus_pct",0))==35,"axe:shieldbreaker_plus35_vs_shield")
	_check(int(Dictionary(defs["ABI512"]).get("shield_damage_bonus_pct",0))==50,"axe:shieldbreaker_e_plus50_vs_shield")

func _mace_abi_cross_integration() -> void:
	var defs := AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH)
	var effs := EffectCatalog.load_json()
	for n in range(601,609):
		var id := "ABI%d" % n
		_check(defs.has(id),id+":approved")
		_check(Array(Dictionary(defs[id]).get("base_damage_by_rank",[])).size()==10,id+":ten_numeric_ranks")
		_check(not Dictionary(defs[id]).has("charge_spend_fraction"),id+":no_old_charge_system")
	_check(not Dictionary(effs["EFF601"]).has("charges_per_ordinary_mh_hit"),"mace:no_passive_charges")
	_check(int(Dictionary(effs["EFF601"]).get("max_stacks",0))==3,"mace:concussion_max3")
	_check(int(Dictionary(effs["EFF601"]).get("duration_rounds",0))==4,"mace:concussion_duration4")
	_check(is_equal_approx(float(Dictionary(effs["EFF602"]).get("incoming_damage_physical_direct_pct",0)),-15.0),"mace:guard15")
	_check(is_equal_approx(float(Dictionary(effs["EFF603"]).get("incoming_damage_physical_direct_pct",0)),-10.0),"mace:counter10")
	_check(is_equal_approx(float(Dictionary(effs["EFF604"]).get("physical_damage_outgoing_direct_pct",0)),-25.0),"mace:enemy_weakening25")
	_check(is_equal_approx(float(Dictionary(effs["EFF605"]).get("physical_damage_outgoing_direct_pct",0)),15.0),"mace:self_damage15")
	_check(is_equal_approx(float(Dictionary(effs["EFF606"]).get("armour_reduction_raw_pct",0)),15.0),"mace:armour_raw_cut15")
	var ctx := _pair("hammer","axe")
	var state: CombatState = ctx["state"]
	var actor := state.get_combatant("left")
	var target := state.get_combatant("right")
	_effect(ctx,"left","left","EFF602",{},true)
	_check(is_equal_approx(CombatModifierService.modifier(actor,"incoming_damage_physical_direct_pct",state.round_number),-15.0),"mace:guard_buff_active")
	_effect(ctx,"left","left","EFF603",{},true)
	_check(is_equal_approx(CombatModifierService.modifier(actor,"incoming_damage_physical_direct_pct",state.round_number),-15.0),"mace:strongest_guard_wins")
	_effect(ctx,"left","right","EFF601",{"stacks_to_apply":3},true)
	_check(HammerAbiCombatService._concussion(target,"left",state.round_number)==3,"mace:concussion_target3")
	_check(HammerAbiCombatService._concussion(target,"other",state.round_number)==0,"mace:concussion_per_source")
	HammerAbiCombatService._consume_concussion(target,"left",1)
	_check(HammerAbiCombatService._concussion(target,"left",state.round_number)==2,"mace:concussion_partial_consume")
	var attack := _attack(ctx,"left","right",0,{"hammer_abi_id":"ABI607","hammer_tempo_control_on_hit":50.0})
	_check(String(attack.result.get("outcome",""))=="connected","mace:wave_hits")
	_check(is_equal_approx(float(attack.result.get("tempo_control_applied",0)),50.0),"mace:tempo_50_shared_engine")
	var ordinary := _attack(ctx,"left","right")
	_check(String(ordinary.result.get("outcome",""))=="connected","mace:ordinary_MH_connected")
	_check(_active_effect(actor,"EFF601").is_empty(),"mace:ordinary_MH_no_charge")
	var physical_damage := state.create_event(CombatEvent.Kind.DAMAGE,"right","left",{"amount":1000.0,"damage_type":"physical","source":"mace_defence_test"})
	var unguarded_ctx := _pair("hammer","axe")
	var normal_target := unguarded_ctx["state"].get_combatant("left")
	var normal_event := unguarded_ctx["state"].create_event(CombatEvent.Kind.DAMAGE,"right","left",{"amount":1000.0,"damage_type":"physical","source":"mace_defence_control"})
	unguarded_ctx["engine"].resolve_event(normal_event)
	ctx["engine"].resolve_event(physical_damage)
	_check(int(physical_damage.result.get("final_damage",0))<=int(normal_event.result.get("final_damage",0)),"mace:physical_guard_reduces_damage")
	var magic_before := CombatModifierService.magic_resist(target,"fire",state.round_number,actor)
	_check(is_equal_approx(magic_before,CombatModifierService.magic_resist(target,"fire",state.round_number,actor)),"mace:concussion_not_magic_resistance")
	var fracture := _effect(ctx,"left","right","EFF606",{},true)
	_check(bool(fracture.result.get("resolved",false)),"mace:armour_debuff_effect")
	_check(is_equal_approx(float(Dictionary(_active_effect(target,"EFF606").get("definition",{})).get("armour_reduction_raw_pct",0)),15.0),"mace:armour_debuff_owned_by_EFF")


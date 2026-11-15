extends SceneTree

## Real four-archetype axe ABI501–516, wound EFF501 and weapon hand integration.
var problems: Array[String] = []

const KITS := {
	"AXE_DEF":["ABI501","ABI502","ABI503","ABI504"],
	"AXE_ATTACK":["ABI505","ABI506","ABI507","ABI508"],
	"AXE_SHIELD":["ABI509","ABI510","ABI511","ABI512"],
	"2H_AXE":["ABI513","ABI514","ABI515","ABI516"]
}

func _initialize() -> void:
	call_deferred("_verify")

func _check(ok: bool, label: String) -> void:
	if not ok:
		problems.append(label)
		print("AXE_V12_FAIL=",label)

func _effect(target: CombatantState, id: String) -> Dictionary:
	for raw in target.active_effects:
		if String(Dictionary(raw).get("effect_id",""))==id:
			return raw
	return {}

func _attacks(session: ArenaCombatSession, id: String) -> Array[CombatEvent]:
	var result: Array[CombatEvent] = []
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.ATTACK and String(event.payload.get("axe_abi_id",""))==id:
			result.append(event)
	return result

func _session(archetype: String, seed: int) -> ArenaCombatSession:
	var character := CharacterState.new("AXE_"+archetype,"Axe Test",40)
	for key in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		character.progression.base_stats[key]=90
	var repo := ItemRepository.new()
	var hand := "MH" if archetype=="AXE_DEF" else "2H"
	var item := ItemV12InstanceFactory.grant_weapon(character,repo,archetype,40,"purple",seed,hand)
	_check(not item.is_empty(),archetype+"_item_generated")
	if item.is_empty():
		return null
	_check(item.get("abilities",[])==KITS[archetype],archetype+"_four_unique_ABI")
	_check(Array(item.get("slot_usage",[])).size()==(0 if archetype=="AXE_DEF" else 2),archetype+"_hand_ownership")
	_check(character.equip("main_hand",String(item.get("instance_id","")),repo),archetype+"_equipped")
	_check(ItemRepository.from_dict(repo.to_dict()).get_item(String(item.get("instance_id",""))).get("abilities",[])==KITS[archetype],archetype+"_save_load_ABI")
	var session := ArenaCombatSession.new(character,repo)
	var actor := session.fighter(true)
	var victim := session.fighter(false)
	_check(actor!=null and victim!=null,archetype+"_fighters")
	if actor == null or victim == null:
		return null
	actor.hp=100000
	actor.max_hp=100000
	victim.hp=100000
	victim.max_hp=100000
	actor.combat_stats["hit_chance_rating_percent"]=100.0
	victim.combat_stats["dodge_rating_percent"]=0.0
	victim.combat_stats["shield_auto_block_rating_percent"]=0.0
	victim.combat_loadout["can_auto_block"]=false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID]=[]
	var options := session.player_ability_options()
	for i in range(4):
		_check(i<options.size() and String(options[i].get("id",""))==String(Array(KITS[archetype])[i]),archetype+"_slot_"+str(i))
	for id in Array(KITS[archetype]):
		session.ability_scheduler.definitions[String(id)]["rolls"]={"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _cast(session: ArenaCombatSession, id: String) -> bool:
	session.fighter(true).action_points=8
	var result := session.play_round(["chest"],["head","arms"],id)
	_check(bool(result.get("ok",false)),id+"_cast")
	return bool(result.get("ok",false))

func _wound_fixture(session: ArenaCombatSession, stacks: int) -> void:
	var target := session.fighter(false)
	target.active_effects.append({
		"effect_id":"EFF501",
		"definition":Dictionary(EffectCatalog.load_json()["EFF501"]).duplicate(true),
		"source_id":session.player_id,
		"start_round":0,
		"remaining_rounds":5,
		"stacks":stacks,
		"active_stacks":stacks
	})

func _verify() -> void:
	var defs := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var eff := EffectCatalog.load_json()
	_check(AxeAbiCombatService.ABILITIES.size()==16,"sixteen_axe_ABI")
	for n in range(501,517):
		var id := "ABI%d" % n
		_check(defs.has(id),id+"_catalog")
		if defs.has(id):
			_check(AbilityRuntime.validate_definition(id,defs[id]).is_empty(),id+"_definition")
			_check(Array(Dictionary(defs[id]).get("base_damage_by_rank",[])).size()==10,id+"_ten_ranks")
	_check(eff.has("EFF501"),"wound_eff_exists")
	_check(int(Dictionary(eff.get("EFF501",{})).get("max_stacks",0))==3,"wound_three_stacks")
	_check(int(Dictionary(eff.get("EFF501",{})).get("duration_rounds",0))==5,"wound_five_rounds")
	_check(Array(Dictionary(Dictionary(eff.get("EFF501",{})).get("values_by_rank",{})).get("damage",[])).size()==10,"wound_ten_ranks")
	for kit in KITS:
		var session := _session(String(kit),202611160+int(Array(KITS[kit])[0].substr(3)))
		if session == null:
			continue
		var q := String(Array(KITS[kit])[0])
		if _cast(session,q):
			_check(_attacks(session,q).size()>=1,String(kit)+"_q_attacks")
			_check(int(_effect(session.fighter(false),"EFF501").get("stacks",0))>=1,String(kit)+"_q_applies_wound")
	var deep := _session("AXE_ATTACK",202611168)
	if deep != null:
		if _cast(deep,"ABI507"):
			_check(int(_effect(deep.fighter(false),"EFF501").get("stacks",0))==2,"deep_wound_two_stacks")
	var defend := _session("AXE_DEF",202611169)
	if defend != null:
		_wound_fixture(defend,3)
		defend.fighter(true).hp=50000
		if _cast(defend,"ABI504"):
			_check(AxeAbiCombatService._wounds(defend.fighter(false),defend.player_id,defend.state.round_number)==0,"def_e_spends_wounds")
			var heal_seen := false
			for event in defend.state.event_log:
				if event.kind==CombatEvent.Kind.EFFECT and String(event.payload.get("ability_id",""))=="ABI504" and int(event.result.get("healed",0))>0:
					heal_seen=true
			_check(heal_seen,"def_e_heals_real_post_mitigation_damage")
	var execute := _session("AXE_ATTACK",202611170)
	if execute != null:
		_wound_fixture(execute,3)
		execute.fighter(false).hp=30000
		if _cast(execute,"ABI508"):
			var hits := _attacks(execute,"ABI508")
			_check(hits.size()==1,"execute_one_attack")
			_check(AxeAbiCombatService._wounds(execute.fighter(false),execute.player_id,execute.state.round_number)==0,"execute_wounds_spent")
	var shield := _session("AXE_SHIELD",202611171)
	if shield != null:
		_wound_fixture(shield,3)
		if _cast(shield,"ABI512"):
			var hits := _attacks(shield,"ABI512")
			_check(hits.size()==1,"shieldbreaker_one_attack")
			if not hits.is_empty():
				_check(bool(hits[0].payload.get("skip_auto_block",false)),"shieldbreaker_skips_auto_block_only")
	var aoe := _session("2H_AXE",202611172)
	if aoe != null:
		for i in range(4):
			var id := "AXE_EXTRA_"+str(i)
			var enemy := CharacterCombatBuilder.build(CharacterState.new(id,id,40),ItemRepository.new(),{"health":100000,"mana":0})
			aoe.state.add_combatant(enemy)
			aoe.orchestrator.group_state.add_member("enemy",id)
			aoe.orchestrator.zone_state.set_zone(id,CombatZoneState.ZONE_2)
			enemy.combat_stats["dodge_rating_percent"]=0.0
			enemy.combat_loadout["can_auto_block"]=false
		if _cast(aoe,"ABI515"):
			_check(_attacks(aoe,"ABI515").size()==5,"aoe_five_independent_attacks")
	print("AXE_V12_ABI_EFF=",("PASS" if problems.is_empty() else "FAIL")," problems=",problems)
	quit(0 if problems.is_empty() else 1)

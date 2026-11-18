extends SceneTree

## 14 unique physical v1.2 archetypes, 91 unique 1v1 pairs, 50 duels per pair.
## Test only: canonical CombatEngine, actual ABI/EFF/AP/CD and real item rolls.
## No artificial charge priming, previous-round trigger markers, or damage buffs.
const LEVEL := 40
## Synthetic duel builds, not permanent character statistics.
## DEF and pure-attack endpoints are explicit; hybrids interpolate by role.
## Existing attack counts, manual block-zone limits, ABI and EFF remain canonical.
const BUILD_PROFILES := {
	"SWORD_DEF": {"armour":45.0,"block":10.0,"dodge":5.0,"hp":2000},
	"DAGGER_DEF": {"armour":25.0,"block":10.0,"dodge":30.0,"hp":1500},
	"AXE_DEF": {"armour":45.0,"block":10.0,"dodge":5.0,"hp":2000},
	"HAMMER_DEF": {"armour":45.0,"block":10.0,"dodge":5.0,"hp":2300},
	"SWORD_DODGE": {"armour":20.0,"block":0.0,"dodge":30.0,"hp":1400},
	"SWORD_CRIT": {"armour":20.0,"block":0.0,"dodge":5.0,"hp":1000},
	"2H_SWORD": {"armour":25.0,"block":0.0,"dodge":5.0,"hp":1200},
	"DAGGER_ATTACK": {"armour":20.0,"block":0.0,"dodge":10.0,"hp":1100},
	"DAGGER_PEN": {"armour":25.0,"block":0.0,"dodge":10.0,"hp":1200},
	"AXE_ATTACK": {"armour":20.0,"block":0.0,"dodge":5.0,"hp":1000},
	"AXE_CRUSHER": {"armour":30.0,"block":0.0,"dodge":5.0,"hp":1300},
	"2H_AXE": {"armour":25.0,"block":0.0,"dodge":5.0,"hp":1200},
	"2H_HAMMER": {"armour":30.0,"block":0.0,"dodge":5.0,"hp":1700},
	"2H_SPEAR": {"armour":25.0,"block":0.0,"dodge":10.0,"hp":1200}
}
const DEFAULT_BATTLES := 50
const MAX_ROUNDS := 300
const BASE_SEED := 202611180
const REPORT_PATH := "res://test-results/physical-archetype-duels"
const SHIELD_ARCHETYPES := ["SWORD_DEF","AXE_DEF","HAMMER_DEF"]
const DEFENCE_ZONES := ["head","chest","arms","waist","legs"]
var failures: Array[String] = []
var trace_rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _armour_rating(target_percent: float) -> float:
	var low := 0.0
	var high := 10000.0
	for _step in range(35):
		var mid := (low+high)*0.5
		if CombatRatingCurves.diminishing(CombatRatingCurves.armour_raw_pct(mid,LEVEL),"armour") < target_percent:
			low=mid
		else:
			high=mid
	return (low+high)*0.5

func _prepare(character_id: String, archetype: String, index: int) -> Dictionary:
	var character := CharacterState.new(character_id,archetype,LEVEL)
	character.progression.level=LEVEL
	character.level=LEVEL
	var repository := ItemRepository.new()
	var weapon := PhysicalDamageBenchmarkFixture.create_weapon(character,repository,archetype,LEVEL,BASE_SEED+index)
	if weapon.is_empty():
		return {}
	if WeaponHandPolicy.DUAL_ARCHETYPES.has(archetype):
		var offhand := PhysicalDamageBenchmarkFixture.create_offhand_weapon(character,repository,archetype,LEVEL,BASE_SEED+index)
		if offhand.is_empty():
			return {}
	if SHIELD_ARCHETYPES.has(archetype):
		# Real canonical shield, not a synthetic free block. Same item on all
		# three defensive 1H archetypes; no shield for 2H or dual wield.
		var shield_id := character_id+"_audit_shield"
		var shield := ItemTemplateService.resolve({"template_id":"shield","instance_id":shield_id})
		if shield.is_empty():
			return {}
		ItemDurabilityService.initialize_item(shield,100)
		if not repository.add_item(shield) or not character.receive_item(shield_id,repository):
			return {}
		if not character.equip("off_hand",shield_id,repository):
			return {}
	return {"character":character,"repository":repository,"weapon":weapon,
		"abilities":Array(weapon.get("abilities",[])).duplicate()}

func _runtime(prepared: Dictionary, archetype: String, armour_ratings: Dictionary) -> CombatantState:
	var build: Dictionary = BUILD_PROFILES.get(archetype,{})
	if build.is_empty():
		return null
	var actor := CharacterCombatBuilder.build(prepared["character"],prepared["repository"],{"health":int(build["hp"])})
	if actor==null:
		return null
	PhysicalDamageBenchmarkFixture.prepare_actor(actor,archetype,prepared["weapon"])
	# The build table is the sole PvP role owner. It does not replace
	# offensive CRIT/PEN specialisation or canonical ABI/EFF definitions.
	var armour := float(armour_ratings.get(build["armour"],0.0))
	for zone in DEFENCE_ZONES:
		actor.armour[zone]={"slashing":armour,"piercing":armour,"chopping":armour,"blunt":armour}
	actor.combat_stats["dodge_rating_percent"]=float(build["dodge"])
	actor.combat_stats["shield_auto_block_rating_percent"]=float(build["block"])
	# Block is only actionable with an actual shield. No virtual shields.
	actor.combat_loadout["can_auto_block"]=SHIELD_ARCHETYPES.has(archetype)
	# Respect the existing PAR073 manual-block capacity and actual shield
	# availability. A dual-wield dagger does not acquire a virtual shield.
	actor.combat_loadout["can_manual_block"]=SHIELD_ARCHETYPES.has(archetype)
	return actor

func _clean(source: Dictionary, keys: Array[String]) -> Dictionary:
	var result := {}
	for key in keys:
		if source.has(key):
			result[key] = source[key]
	return result

func _effects(actor: CombatantState) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw in actor.active_effects:
		var entry: Dictionary = raw
		rows.append(_clean(entry,["effect_id","source_id","stacks","active_stacks","start_round","remaining_rounds","visible_remaining_rounds","revealed"]))
	return rows

func _trace_event(event: CombatEvent) -> Dictionary:
	var kinds := ["ACTION","ATTACK","DAMAGE","EFFECT"]
	return {
		"id":event.event_id,
		"parent":event.parent_event_id,
		"kind":kinds[int(event.kind)],
		"source":event.source_id,
		"target":event.target_id,
		"intent":_clean(event.payload,["ability_id","combo_abi_id","axe_abi_id","weapon_index","is_weapon_attack","effect_id","source_type","source","zone","damage_type","raw_damage","amount","inline_heal","inline_mana","stacks_to_apply","uses_physical_block","axe_heal_from_damage_pct","axe_wounds_snapshot","dagger_armour_bypass_pct"]),
		"result":_clean(event.result,["outcome","partial_block","block_damage_multiplier","manual_block_crushed","auto_block_crushed","dodge_chance","dodge_roll","auto_block_chance","auto_block_roll","hit_chance","hit_roll","critical","crit_chance","raw_damage","armour_reduction","armour_raw_percent","armour_after_breach_percent","after_armour_damage","final_damage","damage_reduction","hp_before","hp_after","healed","effect_id","stacks_applied","resolved","child_event_ids","ap_gained_on_hit"])
	}

func _duel(left: Dictionary, right: Dictionary, left_name: String, right_name: String,
		pair_index: int, battle_index: int, armour_ratings: Dictionary) -> Dictionary:
	var a := _runtime(left,left_name,armour_ratings)
	var b := _runtime(right,right_name,armour_ratings)
	if a==null or b==null:
		return {"outcome":"setup_failed"}
	var state := CombatState.new()
	# Alternate insertion and action locking to cancel any stable first-side bias.
	var reverse := (battle_index % 2)==1
	if reverse:
		state.add_combatant(b)
		state.add_combatant(a)
	else:
		state.add_combatant(a)
		state.add_combatant(b)
	var group := GroupCombatState.new(state)
	group.add_member("A",a.combatant_id)
	group.add_member("B",b.combatant_id)
	group.set_active_opponent(a.combatant_id,b.combatant_id)
	group.set_active_opponent(b.combatant_id,a.combatant_id)
	var zones := CombatZoneState.new(group)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	zones.set_zone(a.combatant_id,CombatZoneState.ZONE_2)
	zones.set_zone(b.combatant_id,CombatZoneState.ZONE_2)
	var engine := CombatEngine.new(state)
	var orchestrator := RoundOrchestrator.new(state,engine,group,zones)
	var loadouts := {a.combatant_id:left["abilities"],b.combatant_id:right["abilities"]}
	var scheduler := AbilityScheduler.new(AbilityCatalog.load_json(AbilityCatalog.CANONICAL_PATH),loadouts)
	var seed := BASE_SEED + pair_index*100003 + battle_index
	engine.combat_rng.seed=seed
	var pipeline := CombatAttackPipeline.new(state,seed,engine)
	var cursor := {a.combatant_id:0,b.combatant_id:0}
	var casts := {a.combatant_id:0,b.combatant_id:0}
	var outcome := "timeout"
	var event_offset := 0
	for turn in range(MAX_ROUNDS):
		var round := orchestrator.begin_round()
		var planned_abilities := {}
		var planned_guards := {}
		var order: Array = [b,a] if reverse else [a,b]
		for actor in order:
			var fighter: CombatantState = actor
			var target: CombatantState = b if fighter==a else a
			# Existing PAR073, not this benchmark, determines the number of
			# manual block zones. Vary only the selected zones across rounds.
			if fighter.can_manual_block():
				var zones_to_block: Array[String] = []
				var block_count := mini(DEFENCE_ZONES.size(),CombatModifierService.manual_block_zone_capacity(fighter))
				for block_index in range(block_count):
					zones_to_block.append(DEFENCE_ZONES[(turn+pair_index+battle_index+block_index)%DEFENCE_ZONES.size()])
				fighter.combat_stats["manual_block_zones"]=zones_to_block
				planned_guards[fighter.combatant_id] = zones_to_block.duplicate()
			var actor_id := fighter.combatant_id
			var decision := PhysicalDamageBenchmarkPolicy.choose(
				loadouts[actor_id],scheduler.definitions,
				scheduler.cooldowns_by_combatant.get(actor_id,{}),state.round_number,
				fighter.action_points,fighter.max_action_points,int(cursor[actor_id]))
			var ability_id := String(decision.get("id",""))
			if not ability_id.is_empty():
				var definition: Dictionary = scheduler.definitions.get(ability_id,{})
				var target_id := actor_id if String(definition.get("target_team","")).to_upper()=="ALLY" else target.combatant_id
				var action := scheduler.cast_event(state,actor_id,target_id,ability_id)
				if action!=null:
					round.lock_action(action)
					cursor[actor_id]=int(decision.get("cursor",cursor[actor_id]))
					casts[actor_id]=int(casts[actor_id])+1
					planned_abilities[actor_id] = ability_id
			pipeline.lock_basic_attack(round,fighter,target)
		orchestrator.resolve_locked_actions(round)
		var result := orchestrator.end_round()
		var events: Array[Dictionary] = []
		for event_index in range(event_offset,state.event_log.size()):
			events.append(_trace_event(state.event_log[event_index]))
		event_offset = state.event_log.size()
		trace_rows.append({
			"round":state.round_number,
			"selected_abilities":planned_abilities,
			"manual_guards":planned_guards,
			"state":{"A_hp":a.visible_hp(),"A_ap":a.action_points,"A_effects":_effects(a),
				"B_hp":b.visible_hp(),"B_ap":b.action_points,"B_effects":_effects(b)},
			"events":events
		})
		outcome=String(result.get("battle_outcome","ongoing"))
		if outcome!="ongoing":
			break
	if outcome=="winner:A":
		outcome="A"
	elif outcome=="winner:B":
		outcome="B"
	elif outcome!="draw":
		outcome="timeout"
	return {"outcome":outcome,"rounds":state.round_number,
		"hp_a":a.visible_hp(),"hp_b":b.visible_hp(),
		"casts_a":int(casts[a.combatant_id]),"casts_b":int(casts[b.combatant_id])}

func _run() -> void:
	var archetypes: Array = ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.duplicate()
	var cases := ["DAGGER_ATTACK","DAGGER_PEN"]
	var armour_ratings := {}
	for archetype in BUILD_PROFILES:
		var value := float(Dictionary(BUILD_PROFILES[archetype])["armour"])
		if not armour_ratings.has(value):
			armour_ratings[value] = _armour_rating(value)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test-results/physical-diagnostic"))
	for opponent in cases:
		var i := archetypes.find("AXE_DEF")
		var j := archetypes.find(opponent)
		if i<0 or j<0:
			failures.append("missing_archetype_"+opponent)
			continue
		var pair_index := 0
		for ai in range(archetypes.size()):
			for bi in range(ai+1,archetypes.size()):
				if ai == mini(i,j) and bi == maxi(i,j):
					break
				pair_index += 1
			if pair_index<91 and ai == mini(i,j):
				break
		var left := _prepare("DUEL_A", "AXE_DEF", i)
		var right := _prepare("DUEL_B", opponent, j)
		if left.is_empty() or right.is_empty():
			failures.append("prepare_"+opponent)
			continue
		trace_rows.clear()
		# Deterministic battle index 0, identical actual runtime and ability scheduler.
		var result := _duel(left,right,"AXE_DEF",opponent,pair_index,0,armour_ratings)
		if String(result.get("outcome","")) == "setup_failed":
			failures.append("duel_setup_"+opponent)
			continue
		var totals := {"A_dealt":0,"B_dealt":0,"A_healed":0,"B_healed":0,"A_manual_blocks":0,"B_manual_blocks":0,"A_auto_blocks":0,"B_auto_blocks":0,"A_dodges":0,"B_dodges":0,"A_abi_casts":int(result["casts_a"]),"B_abi_casts":int(result["casts_b"])}
		for record in trace_rows:
			for event in record["events"]:
				var source := "A" if String(event["source"])=="DUEL_A" else "B"
				var target := "A" if String(event["target"])=="DUEL_A" else "B"
				var kind := String(event["kind"])
				var outcome := String(Dictionary(event["result"]).get("outcome",""))
				if kind=="DAMAGE":
					totals[source+"_dealt"]+=int(Dictionary(event["result"]).get("final_damage",0))
				if kind=="EFFECT":
					totals[target+"_healed"]+=int(Dictionary(event["result"]).get("healed",0))
				if kind=="ATTACK":
					if outcome=="manual_block" or String(Dictionary(event["result"]).get("partial_block",""))=="manual_block":
						totals[target+"_manual_blocks"]+=1
					if outcome=="auto_block" or String(Dictionary(event["result"]).get("partial_block",""))=="auto_block":
						totals[target+"_auto_blocks"]+=1
					if outcome=="dodge":
						totals[target+"_dodges"]+=1
		var report := {"archetype_a":"AXE_DEF","archetype_b":opponent,
			"level":LEVEL,"pair_index":pair_index,"battle_index":0,
			"seed":BASE_SEED+pair_index*100003,"builds":{"A":BUILD_PROFILES["AXE_DEF"],"B":BUILD_PROFILES[opponent]},
			"result":result,"totals":totals,"rounds":trace_rows.duplicate(true)}
		var filename: String = "res://test-results/physical-diagnostic/axe_def_vs_"+String(opponent).to_lower()+".json"
		var file := FileAccess.open(ProjectSettings.globalize_path(filename),FileAccess.WRITE)
		if file==null:
			failures.append("write_"+opponent)
			continue
		file.store_string(JSON.stringify(report,"  "))
		file.close()
		print("DIAGNOSTIC_DUEL=",opponent," rounds=",result["rounds"]," winner=",result["outcome"],
			" hp_A=",result["hp_a"]," hp_B=",result["hp_b"]," totals=",JSON.stringify(totals),
			" file=",filename)
	print("PHYSICAL_DIAGNOSTIC=", "PASS" if failures.is_empty() else "FAIL", " failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

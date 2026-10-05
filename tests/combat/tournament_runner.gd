extends SceneTree

const FIGHTERS := ["TEST_DAGGER_FIGHTER","TEST_SWORD_FIGHTER","TEST_AXE_FIGHTER","TEST_SHIELD_FIGHTER"]
const HIT_ZONES := ["head","chest","arms","waist","legs"]
const FIGHTS_PER_PAIR := 100

func _init() -> void:
	var balance := TestFixtureLoader.load_json("res://data/balance/physical_combat.json")
	var effect_data := TestFixtureLoader.load_json("res://data/test/effects.json")
	var effect_map := {}
	for effect in effect_data.get("effects",[]): effect_map[String(effect.get("id",""))] = effect
	balance["effects"] = effect_map
	var all_ok := EquipmentFixtureCases.run() and PhysicalAttackCases.run(balance) and DuelSmokeCases.run(balance)
	if not all_ok: printerr("BATTLE_OF_ARTHEON_TESTS=FAIL"); quit(1); return
	print("BATTLE_OF_ARTHEON_TESTS=PASS")
	print("FOURTH_COMBAT_TOURNAMENT_WITH_EFF fights_per_pair=",FIGHTS_PER_PAIR)
	for i in range(FIGHTERS.size()):
		for j in range(i+1,FIGHTERS.size()): print(JSON.stringify(_run_pair(FIGHTERS[i],FIGHTERS[j],balance)))
	quit(0)

func _new_stats() -> Dictionary:
	return {"attacks":0,"miss":0,"dodges":0,"manual_blocks":0,"auto_blocks":0,"connected":0,"crits":0,"damage_dealt":0,"damage_taken":0,"eff001":0,"eff002":0,"eff003":0,"eff004":0,"healing":0}
func _run_pair(first_id:String,second_id:String,balance:Dictionary)->Dictionary:
	var wins := {first_id:0,second_id:0,"draw":0,"timeout":0}; var stats := {first_id:_new_stats(),second_id:_new_stats()}; var total_rounds:=0
	for n in range(FIGHTS_PER_PAIR):
		var state:=CombatState.new(); var first:=TestFixtureLoader.build_combatant(first_id); var second:=TestFixtureLoader.build_combatant(second_id)
		_randomize_block_zones(first,50000+n*2); _randomize_block_zones(second,50001+n*2); state.add_combatant(first); state.add_combatant(second)
		var result:=CombatSimulator.new(state,balance,1000+n).run_duel(first_id,second_id); var outcome:=String(result.get("outcome","timeout"))
		if wins.has(outcome): wins[outcome]+=1
		else: wins["timeout"]+=1
		total_rounds+=int(result.get("rounds",0)); _count_events(state,stats)
	return {"pair":[first_id,second_id],"fights":FIGHTS_PER_PAIR,"wins":wins,"avg_rounds":float(total_rounds)/FIGHTS_PER_PAIR,"fighter_stats":stats}
func _randomize_block_zones(combatant:CombatantState,seed_value:int)->void:
	var rng:=RandomNumberGenerator.new(); rng.seed=seed_value; var available:=HIT_ZONES.duplicate(); var selected:Array=[]; var capacity:=int(combatant.combat_stats.get("manual_block_zone_capacity",0))
	while selected.size()<capacity and not available.is_empty(): var index:=rng.randi_range(0,available.size()-1); selected.append(available[index]); available.remove_at(index)
	EquipmentBuilder.set_manual_block_zones(combatant,selected)
func _count_events(state:CombatState,stats:Dictionary)->void:
	for event in state.event_log:
		if event.kind==CombatEvent.Kind.ATTACK:
			if not stats.has(event.source_id) or not stats.has(event.target_id): continue
			var source:Dictionary=stats[event.source_id]; var target:Dictionary=stats[event.target_id]; source["attacks"]+=1; var outcome:=String(event.result.get("outcome",""))
			match outcome:
				"miss": source["miss"]+=1
				"dodge": target["dodges"]+=1
				"manual_block": target["manual_blocks"]+=1
				"auto_block": target["auto_blocks"]+=1
				"connected": source["connected"]+=1
			if bool(event.result.get("critical",false)): source["crits"]+=1
		elif event.kind==CombatEvent.Kind.DAMAGE:
			if stats.has(event.source_id) and stats.has(event.target_id): var dealt:=int(event.result.get("hp_removed",0)); stats[event.source_id]["damage_dealt"]+=dealt; stats[event.target_id]["damage_taken"]+=dealt
		elif event.kind==CombatEvent.Kind.EFFECT and stats.has(event.source_id):
			var key:=String(event.result.get("effect_id","")).to_lower()
			if stats[event.source_id].has(key): stats[event.source_id][key]+=1
			stats[event.source_id]["healing"]+=int(event.result.get("healed",0))

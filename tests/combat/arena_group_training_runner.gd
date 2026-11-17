extends SceneTree

## The Arena 1v1/1v2/1v3 test uses canonical GroupCombatState and
## CombatEngine, not synthetic ABI hits or expedition NPCs.
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ARENA_GROUP_TRAINING_FAIL=",label)

func session_for(count: int) -> ArenaCombatSession:
	var hero := CharacterState.new("TRAIN_GROUP_"+str(count),"Group training",40)
	for id in ["PAR001","PAR002","PAR003","PAR004","PAR005","PAR006"]:
		hero.progression.base_stats[id]=90
	var repo := ItemRepository.new()
	var item := ItemV12InstanceFactory.grant_weapon(hero,repo,"HAMMER_ATTACK",40,"purple",202611190+count,"2H")
	check(not item.is_empty(),"weapon_"+str(count))
	if item.is_empty():
		return null
	check(hero.equip("main_hand",String(item.get("instance_id","")),repo),"equip_"+str(count))
	var session := ArenaCombatSession.new(hero,repo,count)
	session.fighter(true).max_hp=100000
	session.fighter(true).hp=100000
	session.fighter(true).max_action_points=8
	session.fighter(true).action_points=8
	session.fighter(true).combat_stats["hit_chance_rating_percent"]=100.0
	for enemy_id in session.enemy_ids:
		var npc := session.state.get_combatant(enemy_id)
		check(npc!=null,"npc_"+enemy_id)
		if npc==null:
			continue
		check(npc.max_hp==10000,"npc_10k_"+enemy_id)
		npc.combat_stats["dodge_rating_percent"]=0.0
		npc.combat_stats["shield_auto_block_rating_percent"]=0.0
		npc.combat_loadout["can_auto_block"]=false
		npc.combat_loadout["can_manual_block"]=false
		session.ability_scheduler.loadouts[enemy_id]=[]
	session.ability_scheduler.definitions["ABI607"]["rolls"]={"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
	return session

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for count in [1,2,3]:
		var test := session_for(count)
		if test==null:
			continue
		check(test.enemy_ids.size()==count,"count_"+str(count))
		check(test.commands.group.living_enemies(test.player_id).size()==count,"group_count_"+str(count))
		if count>1:
			check(test.select_training_enemy(test.enemy_ids[1]),"focus_second")
			check(test.focused_enemy_id()==test.enemy_ids[1],"focus_actual")
			check(test.select_training_enemy(test.enemy_ids[0]),"restore_first")
		var result := test.play_round(["chest"],["head","arms"],"ABI607")
		check(bool(result.get("ok",false)),"wave_round_"+str(count))
		var connected := 0
		for event in test.state.event_log:
			if event.kind==CombatEvent.Kind.ATTACK and String(event.payload.get("hammer_abi_id",""))=="ABI607" and String(event.result.get("outcome",""))=="connected":
				connected+=1
		check(connected==count,"wave_connected_"+str(count))
		check(test.fighter(true).action_points==5+count,"wave_ap_"+str(count))
		for enemy_id in test.enemy_ids:
			var target := test.state.get_combatant(enemy_id)
			check(target.hp>0 and target.hp<target.max_hp,"wave_hits_live_"+enemy_id)
		check(test.living_enemy_count()==count,"all_survive_"+str(count))
		var per_target_lines := 0
		for line in Array(result.get("lines",[])):
			if String(line).begins_with("  "):
				per_target_lines+=1
		check(per_target_lines==count,"wave_log_per_target_"+str(count))
	# Simultaneous training dummies should not all swing at the same zone.
	# Verify actual queued/resolved NPC attacks, not merely the plan formula.
	var varied := session_for(3)
	if varied != null:
		var first_round := varied.play_round(["chest"],["head","arms"])
		check(bool(first_round.get("ok",false)),"npc_distinct_zones_first_round_accepted")
		var first_zones: Array[String] = []
		for event in varied.state.event_log:
			if event.kind == CombatEvent.Kind.ATTACK and varied.enemy_ids.has(event.source_id) and int(event.payload.get("round",-1)) == 1:
				var zone := String(event.payload.get("zone",""))
				if not first_zones.has(zone):
					first_zones.append(zone)
		check(first_zones.size()==3,"npc_three_distinct_attack_zones_round_one")
		var second_round := varied.play_round(["chest"],["head","arms"])
		check(bool(second_round.get("ok",false)),"npc_distinct_zones_second_round_accepted")
		var second_zones: Array[String] = []
		for event in varied.state.event_log:
			if event.kind == CombatEvent.Kind.ATTACK and varied.enemy_ids.has(event.source_id) and int(event.payload.get("round",-1)) == 2:
				var zone := String(event.payload.get("zone",""))
				if not second_zones.has(zone):
					second_zones.append(zone)
		check(second_zones.size()==3,"npc_three_distinct_attack_zones_round_two")
		check(first_zones!=second_zones,"npc_attack_zones_rotate_between_rounds")
	# Regression: after finishing target 1, UI must derive the next hit count
	# against a surviving focus before the player selects attack zones.
	var switch_target := session_for(3)
	if switch_target != null:
		var first_id := switch_target.enemy_ids[0]
		var second_id := switch_target.enemy_ids[1]
		var first := switch_target.state.get_combatant(first_id)
		first.death_finalized = true
		first.hp = 0
		check(switch_target.commands.group.active_opponent(switch_target.player_id).is_empty(),"defeated_focus_is_invalid")
		var needed := switch_target.player_attack_count()
		check(needed == 1,"after_first_kill_one_attack_required")
		check(switch_target.focused_enemy_id() == second_id,"after_first_kill_refocuses_second")
		var continued := switch_target.play_round(["chest"],["head","arms"])
		check(bool(continued.get("ok",false)),"after_first_kill_next_round_accepted")
	# Earthquake: distinct 1/2/3 stacks must produce three independent
	# post-armour HP values, bonus percentages and Tempo audit entries.
	var quake := session_for(3)
	if quake != null:
		var catalog := EffectCatalog.load_json()
		for i in range(3):
			var npc := quake.state.get_combatant(quake.enemy_ids[i])
			npc.active_effects.append({
				"effect_id":"EFF601",
				"definition":Dictionary(catalog["EFF601"]).duplicate(true),
				"source_id":quake.player_id,
				"start_round":0,
				"remaining_rounds":4,
				"stacks":i+1,
				"active_stacks":i+1
			})
		quake.ability_scheduler.definitions["ABI608"]["rolls"]={"hit":1,"dodge":100,"auto_block":100,"block_crush":100,"crit":100}
		var result := quake.play_round(["chest"],["head","arms"],"ABI608")
		check(bool(result.get("ok",false)),"quake_round_3")
		var detail_lines: Array[String] = []
		for line in Array(result.get("lines",[])):
			if String(line).begins_with("  "):
				detail_lines.append(String(line))
		check(detail_lines.size()==3,"quake_log_three_targets")
		for n in [1,2,3]:
			var target_line := "манекена %d" % n
			var expected_stacks := "Сотрясение %d → поглощено %d" % [n,n]
			var found := false
			for detail in detail_lines:
				if detail.to_lower().contains(target_line) and detail.contains(expected_stacks) and detail.contains("урона") and detail.contains("Tempo"):
					found=true
			check(found,"quake_target_"+str(n)+"_damage_stacks_tempo")
	# Clamp invalid requested counts without changing production battle rules.
	var clamped := session_for(4)
	if clamped!=null:
		check(clamped.enemy_ids.size()==3,"count_clamped_3")
	print("ARENA_GROUP_TRAINING=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)

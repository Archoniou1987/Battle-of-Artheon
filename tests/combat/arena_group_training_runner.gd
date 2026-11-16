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
	# Clamp invalid requested counts without changing production battle rules.
	var clamped := session_for(4)
	if clamped!=null:
		check(clamped.enemy_ids.size()==3,"count_clamped_3")
	print("ARENA_GROUP_TRAINING=",("PASS" if failures.is_empty() else "FAIL")," failures=",failures)
	quit(0 if failures.is_empty() else 1)

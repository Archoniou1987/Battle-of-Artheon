extends SceneTree

func _initialize()->void:
	var state:=CombatState.new()
	var player:=TestFixtureLoader.new_combatant("PLAYER","Player",5,100)
	player.combat_stats.merge({"weapon_profiles":[{"damage_min":60.0,"damage_max":60.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
	state.add_combatant(player)
	var group:=GroupCombatState.new(state)
	group.add_member("players","PLAYER")
	for i in range(3):
		var id:="E%d"%i
		var enemy:=TestFixtureLoader.new_combatant(id,id,1,50)
		enemy.combat_stats.merge({"weapon_profiles":[{"damage_min":5.0,"damage_max":5.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
		state.add_combatant(enemy)
		group.add_member("enemies",id)
	var simulator:=GroupCombatSimulator.new(TestFixtureLoader.canonicalize_state(state),group)
	var valid:=group.active_opponent("PLAYER")=="E0"
	var r1:=simulator.run_round()
	valid=valid and bool(r1.get("ok",false)) and state.get_combatant("E0").is_death_finalized()
	# A normal player action must hit only the active opponent, never every NPC.
	valid=valid and state.get_combatant("E0").hp==-10
	valid=valid and state.get_combatant("E1").hp==50
	valid=valid and state.get_combatant("E2").hp==50
	var player_damage_targets:Array[String]=[]
	for event in state.event_log:
		if event is CombatEvent and event.kind==CombatEvent.Kind.ATTACK and event.source_id=="PLAYER":
			player_damage_targets.append(event.target_id)
	valid=valid and player_damage_targets.size()==1
	valid=valid and player_damage_targets[0]=="E0"
	# Group combat must use the canonical ATTACK pipeline, not direct DAMAGE.
	var player_attack:CombatEvent=null
	for event in state.event_log:
		if event is CombatEvent and event.kind==CombatEvent.Kind.ATTACK and event.source_id=="PLAYER":
			player_attack=event
			break
	valid=valid and player_attack!=null
	valid=valid and String(player_attack.result.get("outcome",""))=="connected"
	valid=valid and player_attack.payload.has("rolls") and player_attack.payload.has("zone")
	valid=valid and bool(player_attack.payload.get("is_weapon_attack",false))
	valid=valid and group.active_opponent("PLAYER")=="E1" and not simulator.controller.combat_finished()
	simulator.run_round()
	valid=valid and state.get_combatant("E1").is_death_finalized() and group.active_opponent("PLAYER")=="E2"
	var r3:=simulator.run_round()
	valid=valid and state.get_combatant("E2").is_death_finalized()
	valid=valid and simulator.controller.combat_finished() and simulator.controller.winning_team()=="players"
	valid=valid and String(r3.get("battle_outcome",""))=="winner:players"
	valid=valid and player.hp==70
	print("GROUP_COMBAT_SIMULATOR_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

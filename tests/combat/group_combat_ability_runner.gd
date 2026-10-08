extends SceneTree

func _initialize()->void:
	var state:=CombatState.new()
	var player:=CombatantState.new("TEST_DAGGER_FIGHTER","Player",5,100,20)
	player.combat_stats={"main_hand_damage_min":1.0,"main_hand_damage_max":1.0,"hit_modifier":100.0,"crit":0.0}
	state.add_combatant(player)
	var enemy:=CombatantState.new("ENEMY","Enemy",1,100,0)
	enemy.combat_stats={"main_hand_damage_min":0.0,"main_hand_damage_max":0.0,"hit_modifier":100.0,"crit":0.0}
	state.add_combatant(enemy)
	var group:=GroupCombatState.new(state)
	group.add_member("players",player.combatant_id)
	group.add_member("enemies",enemy.combatant_id)
	var simulator:=GroupCombatSimulator.new(state,group)
	var result:=simulator.run_round()
	var valid:=bool(result.get("ok",false))
	var saw_ability:=false
	var saw_ability_damage:=false
	for event in state.event_log:
		if not event is CombatEvent or event.source_id!=player.combatant_id:
			continue
		if event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI001":
			saw_ability=true
			valid=valid and event.target_id=="ENEMY"
		if String(event.payload.get("ability_id",""))=="ABI001" and event.kind in [CombatEvent.Kind.ATTACK,CombatEvent.Kind.DAMAGE]:
			saw_ability_damage=true
	valid=valid and saw_ability and saw_ability_damage
	valid=valid and player.mana==10
	valid=valid and enemy.hp<99
	print("GROUP_COMBAT_ABILITY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

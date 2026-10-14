extends SceneTree

func _initialize()->void:
	var state:=CombatState.new()
	var player:=TestFixtureLoader.new_combatant("TEST_DAGGER_FIGHTER","Player",5,100,20)
	player.combat_stats.merge({"weapon_profiles":[{"damage_min":1.0,"damage_max":1.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
	state.add_combatant(player)
	var enemy:=TestFixtureLoader.new_combatant("ENEMY","Enemy",1,100,0)
	enemy.combat_stats.merge({"weapon_profiles":[{"damage_min":0.0,"damage_max":0.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
	state.add_combatant(enemy)
	var group:=GroupCombatState.new(state)
	group.add_member("players",player.combatant_id)
	group.add_member("enemies",enemy.combatant_id)
	var simulator:=GroupCombatSimulator.new(TestFixtureLoader.canonicalize_state(state),group)
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
	valid=valid and _test_lethal_base_attack_abi_target()
	print("GROUP_COMBAT_ABILITY_TEST="+("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)

func _test_lethal_base_attack_abi_target()->bool:
	var state:=CombatState.new()
	var player:=TestFixtureLoader.new_combatant("TEST_DAGGER_FIGHTER","Player",5,100,20)
	player.combat_stats.merge({"weapon_profiles":[{"damage_min":60.0,"damage_max":60.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
	state.add_combatant(player)
	for id in ["ENEMY_A","ENEMY_B"]:
		var enemy:=TestFixtureLoader.new_combatant(id,id,1,50,0)
		enemy.combat_stats.merge({"weapon_profiles":[{"damage_min":0.0,"damage_max":0.0,"damage_type":"slashing"}],"hit_chance_rating_percent":100.0,"crit_chance_rating_percent":0.0}, true)
		state.add_combatant(enemy)
	var group:=GroupCombatState.new(state)
	group.add_member("players",player.combatant_id)
	group.add_member("enemies","ENEMY_A")
	group.add_member("enemies","ENEMY_B")
	var simulator:=GroupCombatSimulator.new(TestFixtureLoader.canonicalize_state(state),group)
	if group.active_opponent(player.combatant_id)!="ENEMY_A": return false
	var result:=simulator.run_round()
	if not bool(result.get("ok",false)): return false
	var ability_on_first:=false
	var ability_on_second:=false
	for event in state.event_log:
		if not event is CombatEvent or event.source_id!=player.combatant_id:
			continue
		if event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI001":
			if event.target_id=="ENEMY_A": ability_on_first=true
			if event.target_id=="ENEMY_B": ability_on_second=true
	return ability_on_first and not ability_on_second and state.get_combatant("ENEMY_A").is_death_finalized() and state.get_combatant("ENEMY_B").hp==50 and group.active_opponent(player.combatant_id)=="ENEMY_B"

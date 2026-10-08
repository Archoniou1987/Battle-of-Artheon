class_name CombatStressCases
extends RefCounted

static func run()->bool:
	for seed in range(1,101):
		if not _run_case(seed):
			print("COMBAT_STRESS_FAIL seed=",seed)
			return false
	return true

static func _run_case(seed:int)->bool:
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed
	var state:=CombatState.new()
	var group:=GroupCombatState.new(state)
	var zones:=CombatZoneState.new(group)
	zones.set_team_flag("A",CombatZoneState.ZONE_1)
	zones.set_team_flag("B",CombatZoneState.ZONE_3)
	for team_index in range(2):
		var team_id:="A" if team_index==0 else "B"
		for index in range(3):
			var id:="%s%d" % [team_id,index]
			var combatant:=CombatantState.new(id,id,10,100,20)
			combatant.combat_stats["main_hand_damage"]=float(rng.randi_range(5,15))
			state.add_combatant(combatant)
			group.add_member(team_id,id)
			zones.set_zone(id,CombatZoneState.ZONE_1 if team_id=="A" else CombatZoneState.ZONE_3)
	var engine:=CombatEngine.new(state,{})
	var orchestrator:=RoundOrchestrator.new(state,engine,group,zones)
	for round_index in range(999):
		orchestrator.begin_round()
		for team_id in ["A","B"]:
			var enemies:=group.round_present_members("B" if team_id=="A" else "A")
			if enemies.is_empty():
				continue
			for source_id in group.round_present_members(team_id):
				var source:=state.get_combatant(source_id)
				if source==null or source.is_death_finalized():
					continue
				var living:Array[String]=[]
				for enemy_id in enemies:
					var enemy:=state.get_combatant(enemy_id)
					if enemy!=null and not enemy.is_death_finalized():
						living.append(enemy_id)
				if living.is_empty():
					continue
				var target_id:=living[rng.randi_range(0,living.size()-1)]
				group.set_active_opponent(source_id,target_id)
				var distance:=zones.distance(source_id,target_id)
				if distance==0:
					var event:=state.create_event(CombatEvent.Kind.ATTACK,source_id,target_id,{"raw_damage":source.combat_stats.get("main_hand_damage",5.0),"zone":"chest","damage_type":"slashing","rolls":{"hit":rng.randi_range(1,100),"dodge":rng.randi_range(1,100),"crit":rng.randi_range(1,100)}})
					state.queue_event(event)
				elif distance>0:
					var source_zone:=zones.zone_of(source_id)
					var target_zone:=zones.zone_of(target_id)
					var coordinate_step:=signi(target_zone-source_zone)
					orchestrator.queue_movement_request(source_id,source_zone+coordinate_step,rng.randi_range(1,100))
		engine.resolve_pending_events()
		var round_result:=orchestrator.end_round()
		if String(round_result.get("battle_outcome","ongoing"))!="ongoing":
			return true
		for combatant in state.combatants.values():
			if combatant.visible_hp()<0 or combatant.visible_hp()>combatant.max_hp:
				return false
			var zone:=zones.zone_of(combatant.combatant_id)
			if zone<CombatZoneState.MIN_ZONE or zone>CombatZoneState.MAX_ZONE:
				return false
	print("COMBAT_STRESS_NON_TERMINATING seed=",seed," rounds=999")
	return false

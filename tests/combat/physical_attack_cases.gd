class_name PhysicalAttackCases
extends RefCounted

## Deterministic smoke cases for the physical attack pipeline.

static func run(balance: Dictionary) -> bool:
	return (
		_case_miss(balance)
		and _case_dodge(balance)
		and _case_block(balance)
		and _case_counterattack_uses_weapon_profile(balance)
		and _case_connected_zero_damage(balance)
	)


static func _base_state() -> CombatState:
	var state := CombatState.new()
	var attacker := CombatantState.new("hero", "Hero", 10, 100)
	var defender := CombatantState.new("enemy", "Enemy", 10, 100)
	state.add_combatant(attacker)
	state.add_combatant(defender)
	state.begin_round()
	return state


static func _attack(state: CombatState, rolls: Dictionary, damage: float = 20.0) -> CombatEvent:
	return state.create_event(
		CombatEvent.Kind.ATTACK,
		"hero",
		"enemy",
		{"raw_damage": damage, "zone": "chest", "damage_type": "slashing", "rolls": rolls}
	)


static func _case_miss(balance: Dictionary) -> bool:
	var state := _base_state()
	var event := _attack(state, {"hit": 100})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "miss" and state.get_combatant("enemy").hp == 100


static func _case_dodge(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["dodge"] = 40.0
	var event := _attack(state, {"hit": 1, "dodge": 1})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "dodge" and state.get_combatant("enemy").hp == 100


static func _case_block(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").combat_stats["manual_block_zone"] = "chest"
	var event := _attack(state, {"hit": 1, "block_crush": 100})
	CombatEngine.new(state, balance).resolve_event(event)
	return event.result.get("outcome") == "manual_block" and state.get_combatant("enemy").hp == 100


static func _case_counterattack_uses_weapon_profile(balance:Dictionary)->bool:
	var state:=_base_state()
	var attacker:=state.get_combatant("hero")
	var defender:=state.get_combatant("enemy")
	attacker.combat_stats["counterattack"]=100.0
	attacker.combat_stats["weapon_profiles"]=[{
		"weapon_class":"sword","item_level":1,"damage_min":7.0,"damage_max":7.0,"damage_type":"chopping",
		"attack_profiles":[{"id":"counter_profile","delivery_type":"MELEE"}]
	}]
	attacker.combat_stats["main_hand_damage"]=99.0
	attacker.combat_stats["main_hand_damage_type"]="piercing"
	attacker.combat_stats["weapon_on_hit_effects"]=[{"chance":100.0,"effect_id":"EFF001","source_type":"item","source_instance_id":"counter_weapon"}]
	attacker.set_weapon_progress("sword",1)
	attacker.combat_stats["dodge"]=100.0
	defender.combat_stats["counterattack"]=100.0
	var incoming:=state.create_event(CombatEvent.Kind.ATTACK,"enemy","hero",{
		"raw_damage":20.0,"zone":"chest","damage_type":"slashing",
		"rolls":{"hit":1,"dodge":1,"counterattack":1},
		"counterattack_zone":"arms",
		"counterattack_rolls":{"hit":1,"dodge":100,"crit":100,"damage":0.0,"on_hit_effect":1,"counterattack":1}
	})
	state.queue_event(incoming)
	CombatEngine.new(state,balance).resolve_pending_events()
	var counter:CombatEvent=null
	for logged in state.event_log:
		if logged.kind==CombatEvent.Kind.ATTACK and bool(logged.payload.get("is_counterattack",false)):
			if counter!=null: return false
			counter=logged
	if counter==null: return false
	if String(counter.payload.get("attack_profile_id",""))!="counter_profile": return false
	if String(counter.payload.get("damage_type",""))!="chopping" or String(counter.payload.get("zone",""))!="arms": return false
	if not is_equal_approx(float(counter.payload.get("raw_damage",-1.0)),7.0*float(balance.get("counterattack_damage_coefficient",0.8))): return false
	if counter.result.get("outcome")!="connected" or counter.result.has("counterattack_event_id"): return false
	var weapon_proc:=false
	for logged in state.event_log:
		if logged.kind==CombatEvent.Kind.EFFECT and String(logged.payload.get("source_instance_id",""))=="counter_weapon":
			weapon_proc=true
	return weapon_proc


static func _case_connected_zero_damage(balance: Dictionary) -> bool:
	var state := _base_state()
	state.get_combatant("enemy").armour["chest"] = {"slashing": 5000.0}
	var event := _attack(state, {"hit": 1, "crit": 100}, 0.5)
	var engine := CombatEngine.new(state, balance)
	state.queue_event(event)
	engine.resolve_pending_events()
	if state.event_log.size() != 2:
		return false
	var damage_event: CombatEvent = state.event_log[1]
	return (
		event.result.get("outcome") == "connected"
		and damage_event.result.get("final_damage") == 0
		and damage_event.result.get("connected") == true
		and state.get_combatant("enemy").hp == 100
	)

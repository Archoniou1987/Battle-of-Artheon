class_name ExternalActionResolver
extends RefCounted

## Phase 10 policy for enemies outside the primary 1v1 engagement.
## Base attack and ABI are independent rolls and may both trigger.

const DEFAULT_BASE_ATTACK_CHANCE:=25.0
const DEFAULT_ABILITY_CHANCE:=20.0

var group:GroupCombatState
var base_attack_chance:float
var ability_chance:float

func _init(group_state:GroupCombatState,base_chance:float=DEFAULT_BASE_ATTACK_CHANCE,abi_chance:float=DEFAULT_ABILITY_CHANCE)->void:
	group=group_state
	base_attack_chance=clampf(base_chance,0.0,100.0)
	ability_chance=clampf(abi_chance,0.0,100.0)

func decide_for(owner_id:String,rolls_by_npc:Dictionary)->Array[Dictionary]:
	var decisions:Array[Dictionary]=[]
	for npc_id in group.external_enemies(owner_id):
		var npc:=group.combat_state.get_combatant(npc_id)
		if npc==null or not npc.is_alive():
			continue
		var rolls:Dictionary=rolls_by_npc.get(npc_id,{})
		var base_roll:=int(rolls.get("base_attack",100))
		var abi_roll:=int(rolls.get("ability",100))
		if CombatMath.roll_success(base_attack_chance,base_roll):
			decisions.append({"kind":"BASE_ATTACK","source_id":npc_id,"target_id":owner_id,"roll":base_roll})
		if CombatMath.roll_success(ability_chance,abi_roll):
			decisions.append({"kind":"ABILITY","source_id":npc_id,"target_id":owner_id,"roll":abi_roll})
	return decisions

func base_attack_event(decision:Dictionary,payload:Dictionary)->CombatEvent:
	var data:=payload.duplicate(true)
	data["source"]="external_base_attack"
	data["external_action"]=true
	return group.combat_state.create_event(
		CombatEvent.Kind.ATTACK,
		String(decision.get("source_id","")),
		String(decision.get("target_id","")),
		data
	)

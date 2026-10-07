class_name OpportunityActionResolver
extends RefCounted

## Optional extra-action policy for combatants acting outside their primary action.
## This is not an engagement restriction: every combatant still owns a normal primary action.
## Opportunity Base Attack and ABI rolls are independent and may both trigger.

const DEFAULT_BASE_ATTACK_CHANCE:=25.0
const DEFAULT_ABILITY_CHANCE:=20.0

var group:GroupCombatState
var base_attack_chance:float
var ability_chance:float

func _init(group_state:GroupCombatState,base_chance:float=DEFAULT_BASE_ATTACK_CHANCE,abi_chance:float=DEFAULT_ABILITY_CHANCE)->void:
	group=group_state
	base_attack_chance=clampf(base_chance,0.0,100.0)
	ability_chance=clampf(abi_chance,0.0,100.0)

func decide_against(target_id:String,actors:Array[String],rolls_by_actor:Dictionary)->Array[Dictionary]:
	var decisions:Array[Dictionary]=[]
	for actor_id in actors:
		if not group.living_enemies(target_id).has(actor_id):
			continue
		var actor:=group.combat_state.get_combatant(actor_id)
		if actor==null or not actor.is_alive():
			continue
		var rolls:Dictionary=rolls_by_actor.get(actor_id,{})
		var base_roll:=int(rolls.get("base_attack",100))
		var abi_roll:=int(rolls.get("ability",100))
		if CombatMath.roll_success(base_attack_chance,base_roll):
			decisions.append({"kind":"BASE_ATTACK","source_id":actor_id,"target_id":target_id,"roll":base_roll})
		if CombatMath.roll_success(ability_chance,abi_roll):
			decisions.append({"kind":"ABILITY","source_id":actor_id,"target_id":target_id,"roll":abi_roll})
	return decisions

func base_attack_event(decision:Dictionary,payload:Dictionary)->CombatEvent:
	var data:=payload.duplicate(true)
	data["source"]="opportunity_base_attack"
	data["opportunity_action"]=true
	return group.combat_state.create_event(
		CombatEvent.Kind.ATTACK,
		String(decision.get("source_id","")),
		String(decision.get("target_id","")),
		data
	)


func ability_event(decision:Dictionary,ability_id:String,definition:Dictionary,target_ids:Array[String]=[])->CombatEvent:
	var source_id:=String(decision.get("source_id",""))
	var target_id:=String(decision.get("target_id",""))
	var event:=AbilityRuntime.build_action_event(group.combat_state,source_id,target_id,ability_id,definition)
	if not target_ids.is_empty():
		event.payload["target_ids"]=target_ids.duplicate()
	event.payload["opportunity_action"]=true
	return event


func choose_ability(ready_abilities:Array[Dictionary])->Dictionary:
	# Phase 10 baseline policy: caller supplies only currently valid/ready abilities.
	# Higher ai_priority wins; stable input order breaks ties.
	var chosen:Dictionary={}
	var best_priority:=-2147483648
	for ability in ready_abilities:
		if ability.is_empty():
			continue
		var priority:=int(ability.get("ai_priority",0))
		if chosen.is_empty() or priority>best_priority:
			chosen=ability
			best_priority=priority
	return chosen.duplicate(true)

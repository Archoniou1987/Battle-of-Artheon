class_name CombatState
extends RefCounted

## Owns deterministic simulation state for one combat.

var round_number: int = 0
var combatants: Dictionary = {}
var event_log: Array[CombatEvent] = []
var pending_events: Array[CombatEvent] = []
## Delayed ABI intents are snapshotted and replayed once at the target round.
var scheduled_abi_intents: Array[Dictionary] = []
var next_event_id: int = 1
var round_damage_by_target: Dictionary = {}


func add_combatant(combatant: CombatantState) -> void:
	combatants[combatant.combatant_id] = combatant


func get_combatant(combatant_id: String) -> CombatantState:
	return combatants.get(combatant_id) as CombatantState


func begin_round() -> void:
	round_number += 1
	round_damage_by_target.clear()


func create_event(
	kind: CombatEvent.Kind,
	source_id: String,
	target_id: String,
	payload: Dictionary = {},
	parent_event_id: int = -1
) -> CombatEvent:
	var event_payload := payload.duplicate(true)
	event_payload["round"] = round_number
	var event := CombatEvent.new(next_event_id, kind, source_id, target_id, event_payload, parent_event_id)
	next_event_id += 1
	return event


func queue_event(event: CombatEvent) -> void:
	pending_events.append(event)


func record_event(event: CombatEvent) -> void:
	event_log.append(event)


func record_damage(target_id:String,source_id:String,amount:int)->void:
	if target_id.is_empty() or source_id.is_empty() or amount<=0:
		return
	if not round_damage_by_target.has(target_id):
		round_damage_by_target[target_id]={}
	var by_source:Dictionary=round_damage_by_target[target_id]
	by_source[source_id]=int(by_source.get(source_id,0))+amount

func fatal_round_killers(target_id:String)->Array[String]:
	var by_source:Dictionary=round_damage_by_target.get(target_id,{})
	var best:=0
	var killers:Array[String]=[]
	for raw_source in by_source.keys():
		var source_id:=String(raw_source)
		var amount:=int(by_source[raw_source])
		if amount>best:
			best=amount
			killers=[source_id]
		elif amount==best and amount>0:
			killers.append(source_id)
	killers.sort()
	return killers

class_name CombatRound
extends RefCounted

## A round first locks intended root actions, then resolves them.
## Death during resolution does not cancel an action already locked this round.

var number: int
var locked_actions: Array[CombatEvent] = []
var resolved: bool = false


func _init(round_number: int) -> void:
	number = round_number


func lock_action(event: CombatEvent) -> void:
	if resolved:
		return
	locked_actions.append(event)


func resolve(engine: CombatEngine) -> void:
	if resolved:
		return
	for event in locked_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	resolved = true

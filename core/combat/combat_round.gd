class_name CombatRound
extends RefCounted

## A round first locks intended root actions, then resolves them.
## Death during resolution does not cancel an action already locked this round.

var number: int
var locked_actions: Array[CombatEvent] = []
var preparation_actions: Array[CombatEvent] = []
var resolved: bool = false


func _init(round_number: int) -> void:
	number = round_number


func lock_action(event: CombatEvent) -> void:
	if resolved:
		return
	# Preparatory buffs/debuffs/dispels are the only early exception.
	if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("resolution_phase","COMBAT")) == "PREPARATION":
		preparation_actions.append(event)
	else:
		locked_actions.append(event)


func resolve(engine: CombatEngine) -> void:
	if resolved:
		return
	# Resolve surprise preparation after all intents were locked but before
	# the shared physical/damage/healing/control combat calculation.
	for event in preparation_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	for event in locked_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	resolved = true

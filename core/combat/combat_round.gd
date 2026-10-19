class_name CombatRound
extends RefCounted

## Every ABI is committed for THIS round after all choices are locked.
## "instant" executes first, before shared combat calculations.
## "standard" resolves alongside ordinary attacks/damage/healing/control.
## Nothing is scheduled for a future round and death is finalized later.

var number: int
var locked_actions: Array[CombatEvent] = []
var preparation_actions: Array[CombatEvent] = []
var resolved: bool = false

func _init(round_number: int) -> void:
	number = round_number

func lock_action(event: CombatEvent) -> void:
	if resolved:
		return
	if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("source_kind", "")) == "ability":
		var timing: String = String(event.payload.get("application_timing", "standard"))
		if timing == "instant":
			preparation_actions.append(event)
			return
		if timing != "standard":
			push_error("Invalid ABI application_timing: " + timing)
			return
	locked_actions.append(event)

func resolve(engine: CombatEngine) -> void:
	if resolved:
		return
	# Only instant ABI effects modify the conditions of this round's
	# subsequent shared combat resolution.
	for event in preparation_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	for event in locked_actions:
		engine.state.queue_event(event)
	engine.resolve_pending_events()
	resolved = true

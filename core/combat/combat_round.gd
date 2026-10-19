class_name CombatRound
extends RefCounted

## Each round seals intent before resolving. A hand-authored ABI chooses either
## immediate activation (in this round, before weapon calculations) or a
## one-time cast at the beginning of the next round. No component inspection.

var number: int
var locked_actions: Array[CombatEvent] = []
var preparation_actions: Array[CombatEvent] = []
var delayed_actions: Array[CombatEvent] = []
var resolved: bool = false

func _init(round_number: int) -> void:
	number = round_number

func lock_action(event: CombatEvent) -> void:
	if resolved:
		return
	if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("source_kind", "")) == "ability":
		var timing: String = String(event.payload.get("application_timing", "immediate"))
		if timing == "next_round":
			delayed_actions.append(event)
		elif timing == "immediate":
			preparation_actions.append(event)
		else:
			push_error("Unknown ABI application_timing: " + timing)
		return
	locked_actions.append(event)

func resolve(engine: CombatEngine) -> void:
	if resolved:
		return
	var state: CombatState = engine.state
	# Release last round's delayed casts only once. Rebuild the action event
	# using the current round so the journal and EFF phase stay consistent.
	var still_scheduled: Array[Dictionary] = []
	var newly_due: Array[CombatEvent] = []
	for record in state.scheduled_abi_intents:
		if int(record.get("due_round", 999999)) > number:
			still_scheduled.append(record)
			continue
		var frozen_payload: Dictionary = Dictionary(record.get("payload", {})).duplicate(true)
		frozen_payload["application_timing"] = "immediate"
		frozen_payload["scheduled_from_round"] = int(record.get("declared_round", 0))
		var due_event := state.create_event(
			CombatEvent.Kind.ACTION,
			String(record.get("source_id", "")),
			String(record.get("target_id", "")),
			frozen_payload
		)
		newly_due.append(due_event)
	state.scheduled_abi_intents = still_scheduled
	# Payment/cooldown/ABI budget were already committed at declaration;
	# never charge again upon delayed execution.
	for event in delayed_actions:
		state.scheduled_abi_intents.append({
			"due_round": number + 1,
			"declared_round": number,
			"source_id": event.source_id,
			"target_id": event.target_id,
			"payload": event.payload.duplicate(true)
		})
		event.set_result("outcome", "scheduled_next_round")
		state.record_event(event)
	for event in newly_due:
		state.queue_event(event)
	for event in preparation_actions:
		state.queue_event(event)
	engine.resolve_pending_events()
	for event in locked_actions:
		state.queue_event(event)
	engine.resolve_pending_events()
	resolved = true

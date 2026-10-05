class_name CombatEvent
extends RefCounted

## Base immutable-intent / mutable-result event passed through Combat Engine.

enum Kind {
	ATTACK,
	DAMAGE,
	EFFECT,
}

var event_id: int
var kind: Kind
var source_id: String
var target_id: String
var parent_event_id: int
var payload: Dictionary
var result: Dictionary = {}


func _init(
	id: int,
	event_kind: Kind,
	source: String,
	target: String,
	data: Dictionary = {},
	parent_id: int = -1
) -> void:
	event_id = id
	kind = event_kind
	source_id = source
	target_id = target
	payload = data.duplicate(true)
	parent_event_id = parent_id


func set_result(key: String, value: Variant) -> void:
	result[key] = value

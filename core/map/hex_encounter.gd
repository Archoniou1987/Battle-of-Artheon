class_name HexEncounter
extends RefCounted

const TRIGGER_ENTER := "enter"
const TRIGGER_DISCOVER := "discover"
const TRIGGER_INTERACT := "interact"

var encounter_id:String
var trigger_type:String
var consequence_type:String
var payload:Dictionary
var required_flags:Array[String]
var blocked_flags:Array[String]
var once:bool
var active:bool = true
var resolved:bool = false

func _init(id:String, trigger:String, consequence:String, data:Dictionary = {}, p_once:bool = true, p_required_flags:Array[String] = [], p_blocked_flags:Array[String] = [])->void:
	encounter_id = id
	trigger_type = trigger
	consequence_type = consequence
	payload = data.duplicate(true)
	once = p_once
	required_flags = p_required_flags.duplicate()
	blocked_flags = p_blocked_flags.duplicate()

func is_valid()->bool:
	return not encounter_id.is_empty() and [TRIGGER_ENTER, TRIGGER_DISCOVER, TRIGGER_INTERACT].has(trigger_type) and not consequence_type.is_empty()

func can_trigger(flags:Dictionary)->bool:
	if not active or (once and resolved):
		return false
	for flag in required_flags:
		if not bool(flags.get(flag, false)):
			return false
	for flag in blocked_flags:
		if bool(flags.get(flag, false)):
			return false
	return true

func mark_triggered()->void:
	if once:
		resolved = true
		active = false

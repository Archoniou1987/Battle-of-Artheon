class_name HexEncounterService
extends RefCounted

var encounters:Dictionary = {}
var positions:Dictionary = {}
var world_flags:Dictionary = {}

func add_encounter(encounter:HexEncounter, pos:Vector2i, map:TacticalMapState)->bool:
	if encounter == null or not encounter.is_valid() or encounters.has(encounter.encounter_id) or not map.in_bounds(pos):
		return false
	encounters[encounter.encounter_id] = encounter
	positions[encounter.encounter_id] = pos
	return true

func set_flag(flag_id:String, value:bool = true)->void:
	if not flag_id.is_empty():
		world_flags[flag_id] = value

func trigger_at(pos:Vector2i, trigger_type:String)->Array[Dictionary]:
	var results:Array[Dictionary] = []
	for encounter_id in encounters.keys():
		if positions[encounter_id] != pos:
			continue
		var encounter:=encounters[encounter_id] as HexEncounter
		if encounter.trigger_type != trigger_type or not encounter.can_trigger(world_flags):
			continue
		results.append({"encounter_id":encounter.encounter_id, "trigger":encounter.trigger_type, "consequence":encounter.consequence_type, "payload":encounter.payload.duplicate(true)})
		encounter.mark_triggered()
	return results

func on_move(move_result:Dictionary)->Array[Dictionary]:
	if not bool(move_result.get("ok", false)):
		return []
	return trigger_at(move_result.get("to", Vector2i(-1, -1)), HexEncounter.TRIGGER_ENTER)

func discover(pos:Vector2i)->Array[Dictionary]:
	return trigger_at(pos, HexEncounter.TRIGGER_DISCOVER)

func interact(pos:Vector2i)->Array[Dictionary]:
	return trigger_at(pos, HexEncounter.TRIGGER_INTERACT)

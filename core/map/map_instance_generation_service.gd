class_name MapInstanceGenerationService
extends RefCounted

## The production LocationGenerator is the ONLY terrain/content generator.
## This service binds existing generation, regions, patrols, encounters and
## objects to the immutable world-instance identity contract.
## It does not save or own characters, items, NPC outcomes, or live positions.
static func generate(instance_data: Dictionary, settlements: Dictionary) -> Dictionary:
	var issue := WorldInstanceContract.validate_instance(instance_data,settlements)
	if not issue.is_empty():
		return {"ok":false,"reason":issue}
	if String(instance_data["lifecycle"]) == WorldInstanceContract.STATE_CLOSED:
		return {"ok":false,"reason":"map_instance_closed"}
	# Version 1 is pinned to LocationGenerator's current deterministic rules.
	# A different generator version must use an explicit migration/dispatcher;
	# otherwise a saved seed could silently produce a different world.
	if int(instance_data["generation_version"]) != 1:
		return {"ok":false,"reason":"unsupported_generation_version"}
	var generated: Dictionary = LocationGenerator.generate(
		int(instance_data["width"]),
		int(instance_data["height"]),
		int(instance_data["seed"])
	)
	var map: TacticalMapState = generated.get("map",null)
	if map == null or map.width != int(instance_data["width"]) or map.height != int(instance_data["height"]):
		return {"ok":false,"reason":"generated_map_shape_mismatch"}
	var entrance: Vector2i = generated.get("entrance",Vector2i(-1,-1))
	var exit_cell: Vector2i = generated.get("exit",Vector2i(-1,-1))
	if not map.in_bounds(entrance) or not map.in_bounds(exit_cell):
		return {"ok":false,"reason":"generated_map_exits_invalid"}
	if not map.cell(entrance).is_passable() or not map.cell(exit_cell).is_passable():
		return {"ok":false,"reason":"generated_map_exits_blocked"}
	# Leave the full generator result intact: MapRegionGenerator, guard
	# encounters, thematic content and patrol definitions stay available
	# to existing consumers. Do NOT regenerate independently per subsystem.
	return {
		"ok":true,
		"instance":instance_data.duplicate(true),
		"generated":generated
	}

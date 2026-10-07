class_name ResourceToolService
extends RefCounted

const MODE_REQUIRED := "required"
const MODE_BONUS := "bonus"
const MODE_GATHERING := "gathering"

static func equipped_tool(character:CharacterState, repository:ItemRepository)->Dictionary:
	var value:Variant = character.equipment.get_equipped_instance_id("tool")
	if value == null:
		return {}
	var instance_id:=String(value)
	if instance_id.is_empty() or not repository.has_item(instance_id):
		return {}
	var item:=repository.get_item(instance_id)
	if item.is_empty() or not ItemDurabilityService.is_usable(item):
		return {}
	return item

static func evaluate(character:CharacterState, repository:ItemRepository, resource:ResourceDefinition, mode:String)->Dictionary:
	var tool:=equipped_tool(character, repository)
	var matched:=false
	var tool_level:=0
	var bonus_yield:=0
	if not tool.is_empty():
		var categories:Array = tool.get("resource_categories", [])
		tool_level = int(tool.get("tool_level", 0))
		matched = categories.has(resource.category) and tool_level >= resource.level
		if matched:
			bonus_yield = maxi(0, int(tool.get("resource_bonus_yield", 0)))
	var allowed:=true
	if mode == MODE_REQUIRED or mode == MODE_GATHERING:
		allowed = matched
	elif mode != MODE_BONUS:
		allowed = false
	return {"allowed":allowed, "tool_matched":matched, "tool_level":tool_level, "bonus_yield":bonus_yield if matched else 0}

static func apply_bonus(base_quantity:int, evaluation:Dictionary)->int:
	return maxi(0, base_quantity) + maxi(0, int(evaluation.get("bonus_yield", 0)))

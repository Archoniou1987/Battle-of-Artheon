class_name ResourceRepository
extends RefCounted

var _resources:Dictionary = {}

func add_resource(resource:ResourceDefinition)->bool:
	if resource == null or not resource.is_valid() or _resources.has(resource.resource_id):
		return false
	_resources[resource.resource_id] = resource
	return true

func has_resource(resource_id:String)->bool:
	return _resources.has(resource_id)

func get_resource(resource_id:String)->ResourceDefinition:
	if not _resources.has(resource_id):
		return null
	return _resources[resource_id] as ResourceDefinition

func all_resources()->Array[ResourceDefinition]:
	var result:Array[ResourceDefinition] = []
	for resource in _resources.values():
		result.append(resource as ResourceDefinition)
	return result

func resources_for(category:String, min_level:int = 1, max_level:int = 2147483647)->Array[ResourceDefinition]:
	var result:Array[ResourceDefinition] = []
	for resource in _resources.values():
		var definition:=resource as ResourceDefinition
		if definition.category == category and definition.level >= min_level and definition.level <= max_level:
			result.append(definition)
	result.sort_custom(func(a:ResourceDefinition, b:ResourceDefinition)->bool: return a.level < b.level)
	return result

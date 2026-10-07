class_name ResourceSourceRepository
extends RefCounted

var _sources:Dictionary = {}

func add_source(source:ResourceSource, resources:ResourceRepository)->bool:
	if source == null or not source.is_valid(resources) or _sources.has(source.source_id):
		return false
	_sources[source.source_id] = source
	return true

func has_source(source_id:String)->bool:
	return _sources.has(source_id)

func get_source(source_id:String)->ResourceSource:
	if not _sources.has(source_id):
		return null
	return _sources[source_id] as ResourceSource

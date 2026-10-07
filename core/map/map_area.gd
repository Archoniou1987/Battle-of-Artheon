class_name MapArea
extends RefCounted

var area_id:String
var area_type:String
var level:int
var rarity:String
var richness:float
var gathering_time_sec:float
var loot_group_ids:Array[String] = []
var resource_source_ids:Array[String] = []
var depleted:bool = false

func _init(id:String, type:String, p_level:int = 1, p_rarity:String = "common", p_richness:float = 1.0, p_time:float = 60.0)->void:
	area_id = id
	area_type = type
	level = maxi(1, p_level)
	rarity = p_rarity
	richness = maxf(0.0, p_richness)
	gathering_time_sec = maxf(0.0, p_time)

func add_resource_source(source_id:String)->bool:
	if source_id.is_empty() or resource_source_ids.has(source_id):
		return false
	resource_source_ids.append(source_id)
	return true

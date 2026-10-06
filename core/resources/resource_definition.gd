class_name ResourceDefinition
extends RefCounted

var resource_id:String
var display_name:String
var category:String
var level:int
var rarity:String

func _init(id:String, name:String, p_category:String, p_level:int, p_rarity:String = "common")->void:
	resource_id = id
	display_name = name
	category = p_category
	level = maxi(1, p_level)
	rarity = p_rarity

func is_valid()->bool:
	return not resource_id.is_empty() and not display_name.is_empty() and not category.is_empty() and level > 0 and not rarity.is_empty()

class_name ChestState
extends RefCounted

var chest_id: String
var loot_table_id: String
var is_open: bool = false

func _init(id: String, table_id: String) -> void:
	chest_id = id
	loot_table_id = table_id

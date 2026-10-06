class_name NpcInstance
extends RefCounted

var instance_id:String
var template_id:String
var display_name:String
var level:int
var equipment:EquipmentState
var bag:InventoryState

func _init(p_instance_id:String, template:NpcState)->void:
	instance_id=p_instance_id
	template_id=template.npc_id
	display_name=template.display_name
	level=template.level
	equipment=EquipmentState.new()
	bag=InventoryState.new(instance_id)

func receive_item(item_id:String, repository:ItemRepository)->bool:
	return bag.add_instance(item_id,repository)

func equip(slot:String,item_id:String,repository:ItemRepository)->bool:
	return EquipmentService.equip_instance(slot,item_id,bag,equipment,repository)

class_name NpcState
extends RefCounted
var npc_id:String
var template_id:String
var display_name:String
var npc_type:String
var level:int
var rank:String
var aggression:float
var base:Dictionary
var abilities:Array
var traits:Array
var loot_table_id:String
var loot_groups:Array
func _init(data:Dictionary)->void:
	npc_id=String(data.get("id",""))
	template_id=String(data.get("template_id",npc_id))
	display_name=String(data.get("name",""))
	npc_type=String(data.get("type","humanoid"))
	level=maxi(1,int(data.get("level",1)))
	rank=String(data.get("rank","normal"))
	aggression=float(data.get("aggression",0.0))
	base=(data.get("base",{}) as Dictionary).duplicate(true)
	abilities=(data.get("abilities",[]) as Array).duplicate(true)
	traits=(data.get("traits",[]) as Array).duplicate(true)
	loot_table_id=String(data.get("loot_table_id",""))
	loot_groups=(data.get("loot_groups",[]) as Array).duplicate(true)

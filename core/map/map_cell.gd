class_name MapCell
extends RefCounted

var q:int
var r:int
var terrain_id:String
var movement_cost:float
var blocked:bool = false
var obstacle_id:String = ""
var area_ids:Array[String] = []
var object_ids:Array[String] = []
var discovered:bool = false
var visited:bool = false
var effects:Array[String] = []
var triggers:Array[String] = []

func _init(p_q:int, p_r:int, terrain:String = "grass", cost:float = 1.0)->void:
	q = p_q
	r = p_r
	terrain_id = terrain
	movement_cost = maxf(0.0, cost)

func key()->Vector2i:
	return Vector2i(q, r)

func is_passable()->bool:
	return not blocked

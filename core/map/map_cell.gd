class_name MapCell
extends RefCounted

var x:int
var y:int
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

func _init(px:int, py:int, terrain:String = "grass", cost:float = 1.0)->void:
	x = px
	y = py
	terrain_id = terrain
	movement_cost = maxf(0.0, cost)

func key()->Vector2i:
	return Vector2i(x, y)

func is_passable()->bool:
	return not blocked

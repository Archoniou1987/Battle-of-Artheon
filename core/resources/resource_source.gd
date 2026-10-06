class_name ResourceSource
extends RefCounted

var source_id:String
var resource_id:String
var quantity:int
var max_quantity:int
var yield_min:int
var yield_max:int
var gathering_time_sec:float
var recovery_amount:int
var recovery_interval_sec:float

func _init(id:String, p_resource_id:String, p_quantity:int, p_yield_min:int = 1, p_yield_max:int = 1, p_time:float = 60.0, p_recovery_amount:int = 0, p_recovery_interval_sec:float = 0.0)->void:
	source_id = id
	resource_id = p_resource_id
	max_quantity = maxi(0, p_quantity)
	quantity = max_quantity
	yield_min = maxi(1, p_yield_min)
	yield_max = maxi(yield_min, p_yield_max)
	gathering_time_sec = maxf(0.0, p_time)
	recovery_amount = maxi(0, p_recovery_amount)
	recovery_interval_sec = maxf(0.0, p_recovery_interval_sec)

func is_valid(resources:ResourceRepository)->bool:
	return not source_id.is_empty() and resources.has_resource(resource_id) and max_quantity > 0

func is_depleted()->bool:
	return quantity <= 0

func take(requested:int)->int:
	if requested <= 0 or is_depleted():
		return 0
	var taken:=mini(quantity, requested)
	quantity -= taken
	return taken

func recover(ticks:int = 1)->int:
	if recovery_amount <= 0 or ticks <= 0 or quantity >= max_quantity:
		return 0
	var before:=quantity
	quantity = mini(max_quantity, quantity + recovery_amount * ticks)
	return quantity - before

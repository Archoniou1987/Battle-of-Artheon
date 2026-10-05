class_name CombatantState
extends RefCounted

## Runtime combat state. Contains simulation data only; no UI/scene dependencies.

var combatant_id: String
var display_name: String
var level: int
var max_hp: int
var hp: int
var max_mana: int
var mana: int
var action_points: int = 0
var max_action_points: int = 5
var tempo: float = 0.0
var stats: Dictionary = {}
var combat_stats: Dictionary = {}
var armour: Dictionary = {}
var active_effects: Array[Dictionary] = []


func _init(id: String, name: String, character_level: int, health: int, mana_pool: int = 0) -> void:
	combatant_id = id
	display_name = name
	level = maxi(1, character_level)
	max_hp = maxi(0, health)
	hp = max_hp
	max_mana = maxi(0, mana_pool)
	mana = max_mana


func is_alive() -> bool:
	return hp > 0


func apply_damage(amount: int) -> int:
	var applied := mini(hp, maxi(0, amount))
	hp -= applied
	return applied


func restore_hp(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


func spend_mana(amount: int) -> bool:
	var cost := maxi(0, amount)
	if mana < cost:
		return false
	mana -= cost
	return true


func gain_action_points(amount: int) -> int:
	var before := action_points
	action_points = mini(max_action_points, action_points + maxi(0, amount))
	return action_points - before


func spend_action_points(amount: int) -> bool:
	var cost := maxi(0, amount)
	if action_points < cost:
		return false
	action_points -= cost
	return true

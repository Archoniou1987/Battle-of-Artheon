class_name CombatantState
extends RefCounted

## Runtime combat state. Contains simulation data only; no UI/scene dependencies.

var combatant_id: String
var display_name: String
var level: int
var max_hp: int
var hp: int
var death_finalized: bool = false
## Fatal single post-mitigation hit, resolved at the end of the round.
var one_shot_kill: bool = false
var max_mana: int
var mana: int
var action_points: int = 0
var max_action_points: int = 5
## Current accumulated Tempo; negative control debt has no artificial floor.
var tempo: float = 0.0
var base_tempo: float = 0.0
var max_tempo: float = 100.0
var tempo_regen: float = 0.0
## A stun is scheduled for exactly one future round at the end-round threshold.
var tempo_stun_round: int = -1
## Inclusive last immune round, after the stunned round; 0 means none.
var tempo_immunity_until_round: int = 0
var stats: Dictionary = {}
var combat_stats: Dictionary = {}
var armour: Dictionary = {}
var magic_resists: Dictionary = {}
var effect_immunities: Array[String] = []
var active_effects: Array[Dictionary] = []
var weapon_skills: Dictionary = {}
var weapon_xp: Dictionary = {}
var combat_loadout: Dictionary = {}
var combat_loadout_locked: bool = false

func lock_combat_loadout(snapshot:Dictionary)->void:
	combat_loadout=snapshot.duplicate(true)
	combat_loadout_locked=true

func can_manual_block()->bool:
	return bool(combat_loadout.get("can_manual_block",combat_stats.get("can_manual_block",true)))

func can_auto_block()->bool:
	return bool(combat_loadout.get("can_auto_block",combat_stats.get("can_auto_block",true)))

func weapon_skill(weapon_class: String) -> int:
	return clampi(int(weapon_skills.get(weapon_class, 1)), 1, 100)

func weapon_experience(weapon_class: String) -> float:
	return maxf(0.0, float(weapon_xp.get(weapon_class, 0.0)))

func set_weapon_progress(weapon_class: String, skill: int, experience: float = 0.0) -> void:
	if weapon_class.is_empty(): return
	weapon_skills[weapon_class] = clampi(skill, 1, 100)
	weapon_xp[weapon_class] = maxf(0.0, experience)


func _init(id: String, name: String, character_level: int, health: int, mana_pool: int = 0) -> void:
	combatant_id = id
	display_name = name
	level = maxi(1, character_level)
	max_hp = maxi(0, health)
	hp = max_hp
	max_mana = maxi(0, mana_pool)
	mana = max_mana


func is_alive() -> bool:
	return not death_finalized and hp > 0

func is_death_finalized() -> bool:
	return death_finalized


func apply_damage(amount: int) -> int:
	# A finalized death is irreversible within this combat (no resurrection ABI).
	if death_finalized:
		return 0
	var applied := maxi(0, amount)
	hp -= applied
	if applied >= max_hp and max_hp > 0:
		one_shot_kill = true
	return applied


func restore_hp(amount: int) -> int:
	if death_finalized:
		return 0
	var before := hp
	hp += maxi(0, amount)
	return hp - before


func visible_hp() -> int:
	# One-shot can finalize death even when provisional HP remains positive.
	return 0 if death_finalized else clampi(hp, 0, max_hp)


func spend_mana(amount: int) -> bool:
	if death_finalized:
		return false
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

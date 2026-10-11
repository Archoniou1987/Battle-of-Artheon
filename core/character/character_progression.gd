class_name CharacterProgression
extends RefCounted

## Approved level 1–20 progression. No implicit rules beyond level 20.
const XP_TABLE_PATH := "res://data/progression/xp_1_20.json"
const FIRST_LEVEL := 1
const MAX_CONFIGURED_LEVEL := 20

var level: int = FIRST_LEVEL
var xp_into_level: int = 0
var unspent_stat_points: int = 0
var pending_stats: Dictionary = {}
const STARTING_POINTS := 12
## Temporary neutral starting distribution; archetype-specific allocation is not approved yet.
var base_stats: Dictionary = {"STR": 1, "DEX": 1, "INTU": 1, "INT": 1, "WIS": 1, "END": 1}
var _table: Dictionary = {}

func _init(start_level: int = 1, table: Dictionary = {}) -> void:
	level = clampi(start_level, FIRST_LEVEL, MAX_CONFIGURED_LEVEL)
	_table = table.duplicate(true) if not table.is_empty() else load_table()
	# Level-one total is 18. Levels 2–20 gain one distributable point each.
	unspent_stat_points = STARTING_POINTS + level - 1

static func load_table() -> Dictionary:
	if not FileAccess.file_exists(XP_TABLE_PATH):
		return {}
	var file := FileAccess.open(XP_TABLE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func required_xp() -> int:
	var thresholds: Array = _table.get("level_up_xp", [])
	if level < 1 or level > thresholds.size():
		return 0
	return int(thresholds[level - 1])

func gain_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var gained_levels := 0
	if level >= MAX_CONFIGURED_LEVEL:
		return 0 # Level 20 cap: do not accumulate unbounded, unusable XP.
	xp_into_level += amount
	while level < MAX_CONFIGURED_LEVEL:
		var needed := required_xp()
		if needed <= 0 or xp_into_level < needed:
			break
		xp_into_level -= needed
		level += 1
		unspent_stat_points += 1
		gained_levels += 1
	if level >= MAX_CONFIGURED_LEVEL:
		xp_into_level = 0
	return gained_levels

func allocate_stat(stat: String) -> bool:
	if unspent_stat_points <= 0 or not base_stats.has(stat):
		return false
	pending_stats[stat] = int(pending_stats.get(stat, 0)) + 1
	unspent_stat_points -= 1
	return true

func remove_pending_stat(stat: String) -> bool:
	if int(pending_stats.get(stat, 0)) <= 0:
		return false
	pending_stats[stat] = int(pending_stats[stat]) - 1
	if int(pending_stats[stat]) == 0:
		pending_stats.erase(stat)
	unspent_stat_points += 1
	return true

func reset_pending_stats() -> void:
	for value in pending_stats.values():
		unspent_stat_points += int(value)
	pending_stats.clear()

func save_pending_stats() -> bool:
	if pending_stats.is_empty():
		return false
	for stat in pending_stats:
		base_stats[stat] = int(base_stats[stat]) + int(pending_stats[stat])
	pending_stats.clear()
	return true

func displayed_stat(stat: String) -> int:
	return int(base_stats.get(stat, 0)) + int(pending_stats.get(stat, 0))

func npc_xp(player_level: int, npc_level: int, ad_bonus: bool = false) -> int:
	var rewards: Array = _table.get("npc_base_xp", [])
	if npc_level < 1 or npc_level > rewards.size():
		return 0
	var difference := npc_level - player_level
	var multiplier := 1.0
	if difference < 0:
		multiplier = maxf(0.0, 1.0 + float(difference) * 0.2)
	elif difference > 0:
		multiplier = minf(1.25, 1.0 + float(difference) * 0.1)
	var base_xp := int(rewards[npc_level - 1])
	return roundi(base_xp * multiplier * (1.5 if ad_bonus else 1.0))

func to_dict() -> Dictionary:
	return {"level": level, "xp_into_level": xp_into_level, "unspent_stat_points": unspent_stat_points, "base_stats": base_stats.duplicate(true), "pending_stats": pending_stats.duplicate(true)}

func restore(data: Dictionary) -> bool:
	var restored_level := int(data.get("level", 0))
	var restored_xp := int(data.get("xp_into_level", -1))
	var restored_points := int(data.get("unspent_stat_points", -1))
	var restored_stats: Variant = data.get("base_stats", {})
	var restored_pending: Variant = data.get("pending_stats", {})
	if restored_level < 1 or restored_level > MAX_CONFIGURED_LEVEL or restored_xp < 0 or restored_points < 0 or not restored_stats is Dictionary or not restored_pending is Dictionary:
		return false
	var thresholds: Array = _table.get("level_up_xp", [])
	if restored_level < MAX_CONFIGURED_LEVEL and (restored_level > thresholds.size() or restored_xp >= int(thresholds[restored_level - 1])):
		return false
	if restored_level == MAX_CONFIGURED_LEVEL and restored_xp != 0:
		return false
	var keys := ["STR", "DEX", "INTU", "INT", "WIS", "END"]
	var total := restored_points
	for key in keys:
		if not restored_stats.has(key) or not (restored_stats[key] is int) or int(restored_stats[key]) < 1:
			return false
		total += int(restored_stats[key])
	for key in restored_pending:
		if not keys.has(key) or not (restored_pending[key] is int) or int(restored_pending[key]) <= 0:
			return false
		total += int(restored_pending[key])
	if total != 18 + restored_level - 1:
		return false
	level = restored_level
	xp_into_level = restored_xp
	unspent_stat_points = restored_points
	base_stats = restored_stats.duplicate(true)
	pending_stats = restored_pending.duplicate(true)
	return true

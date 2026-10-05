class_name EquipmentBuilder
extends RefCounted

const PHYSICAL_TYPES := ["piercing", "slashing", "chopping", "blunt"]
const HIT_ZONES := ["head", "chest", "arms", "waist", "legs"]

## Builds runtime combat stats from data-only item definitions.
## Passive numeric item stats aggregate; item identity remains outside Combat Engine.

static func equip(combatant: CombatantState, item: Dictionary) -> void:
	var item_stats: Dictionary = item.get("combat_stats", {})
	for stat_name in item_stats:
		combatant.combat_stats[stat_name] = float(combatant.combat_stats.get(stat_name, 0.0)) + float(item_stats[stat_name])

	var damage: Dictionary = item.get("damage", {})
	if not damage.is_empty():
		combatant.combat_stats["main_hand_damage_min"] = float(damage.get("min", 0.0))
		combatant.combat_stats["main_hand_damage_max"] = float(damage.get("max", 0.0))
		# Until variable weapon damage is rolled by the simulator, use midpoint.
		combatant.combat_stats["main_hand_damage"] = (float(damage.get("min", 0.0)) + float(damage.get("max", 0.0))) / 2.0
		combatant.combat_stats["main_hand_damage_type"] = String(damage.get("type", "slashing"))

	var universal_armour := float(item.get("armour_all_zones_all_physical", 0.0))
	if universal_armour > 0.0:
		_add_universal_physical_armour(combatant, universal_armour)


static func _add_universal_physical_armour(combatant: CombatantState, amount: float) -> void:
	for zone in HIT_ZONES:
		var zone_armour: Dictionary = combatant.armour.get(zone, {})
		for damage_type in PHYSICAL_TYPES:
			zone_armour[damage_type] = float(zone_armour.get(damage_type, 0.0)) + amount
		combatant.armour[zone] = zone_armour

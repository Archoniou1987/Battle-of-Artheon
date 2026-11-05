class_name WeaponHandPolicy
extends RefCounted

## Identical item ID / PAR / damage in either hand. Equip slot owns the penalty.
const OFF_HAND_MULTIPLIER := 0.75
const DUAL_ARCHETYPES := [
	"DAGGER_DEF","DAGGER_ATTACK","DAGGER_MAGIC","DAGGER_PEN",
	"SWORD_DODGE","SWORD_CRIT","SWORD_MAGIC",
	"AXE_ATTACK","AXE_SHIELD",
	"HAMMER_ATTACK","HAMMER_MAGIC"
]
## One weapon still supplies one attack (PAR057), not 0.75 attacks.
const STRUCTURAL_PAR_IDS := ["PAR057"]

static func allowed_slots(archetype_id: String) -> Array[String]:
	return ["main_hand","off_hand"] if DUAL_ARCHETYPES.has(archetype_id) else ["main_hand"]

static func par_multiplier(par_id: String, is_off_hand: bool) -> float:
	return OFF_HAND_MULTIPLIER if is_off_hand and not STRUCTURAL_PAR_IDS.has(par_id) else 1.0

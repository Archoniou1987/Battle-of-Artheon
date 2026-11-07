class_name AttackPowerService
extends RefCounted

## v1.2 Attack Power: absolute damage, not a percentage.
## OH item PAR reduction happens once during canonical aggregation.
const RATING_PER_DAMAGE := 5.0
const MAIN_HAND_MULTIPLIER := 0.7
const OFF_HAND_MULTIPLIER := 0.5
const TWO_HANDED_MULTIPLIER := 1.0

static func raw_damage(rating: float) -> float:
	return rating / RATING_PER_DAMAGE

static func damage_bonus(rating: float, hand: String, two_handed: bool = false) -> float:
	if hand == "off_hand":
		return raw_damage(rating) * OFF_HAND_MULTIPLIER
	return raw_damage(rating) * (TWO_HANDED_MULTIPLIER if two_handed else MAIN_HAND_MULTIPLIER)

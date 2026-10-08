class_name CombatMath
extends RefCounted

## Pure combat helpers. Keep presentation, scene state and input out of this layer.

static func roll_success(chance: float, roll: int) -> bool:
	var effective_chance := clampf(chance, 0.0, 100.0)
	return roll >= 1 and roll <= 100 and float(roll) <= effective_chance


static func effective_dodge(dodge: float, anti_dodge: float) -> float:
	return clampf(dodge - anti_dodge, 0.0, 100.0)


static func effective_crit(crit: float, anti_crit: float) -> float:
	return clampf(crit - anti_crit, 0.0, 100.0)


static func effective_armour(raw_armour: float, flat_penetration: float, percent_reduction: float) -> float:
	var after_flat := maxf(0.0, raw_armour - maxf(0.0, flat_penetration))
	var reduction := clampf(percent_reduction, 0.0, 1.0)
	return after_flat * (1.0 - reduction)


static func final_damage_floor(value: float) -> int:
	return maxi(0, int(floor(value)))


static func roll_damage(damage_min:float,damage_max:float,roll:float)->float:
	var low:=minf(damage_min,damage_max)
	var high:=maxf(damage_min,damage_max)
	if is_equal_approx(low,high):
		return low
	var normalized:=clampf(roll,0.0,1.0)
	return lerpf(low,high,normalized)

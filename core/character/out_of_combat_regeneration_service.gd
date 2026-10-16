class_name OutOfCombatRegenerationService
extends RefCounted

## Offline and online use exactly the same elapsed-time calculation.
## PAR012: percentage points of MaxHP / 10 seconds.
## PAR013: flat mana / 10 seconds; PAR017: flat HP / 10 seconds.
## Fractional progress is persisted on CharacterState (never per-frame rounded).
const INTERVAL_SECONDS := 10.0

static func advance(character: CharacterState, repository: ItemRepository, elapsed_seconds: float) -> bool:
	if character == null or repository == null or character.in_combat:
		return false
	if not is_finite(elapsed_seconds) or elapsed_seconds <= 0.0:
		return false
	var par := ParCalculationService.calculate(character, repository)
	if par.is_empty():
		return false
	var totals: Dictionary = par["totals"]
	var resources := character.resource_snapshot(repository, par)
	if resources.is_empty() or int(resources["hp"]) <= 0:
		# Recovery from death is an explicit game rule, not passive regeneration.
		return false
	var max_hp := int(resources["max_hp"])
	var max_mana := int(resources["max_mana"])
	var hp_rate := maxf(0.0, float(totals.get("PAR012", 0.0))) * float(max_hp) / 100.0
	hp_rate += maxf(0.0, float(totals.get("PAR017", 0.0)))
	var mana_rate := maxf(0.0, float(totals.get("PAR013", 0.0)))
	if not is_finite(hp_rate) or not is_finite(mana_rate):
		push_error("Invalid PAR012/PAR013/PAR017 regeneration rate")
		return false
	var before_hp := character.current_hp
	var before_mana := character.current_mana
	var before_hp_fraction := character.out_combat_hp_fraction
	var before_mana_fraction := character.out_combat_mana_fraction
	var cycles := elapsed_seconds / INTERVAL_SECONDS
	if character.current_hp < max_hp:
		var hp_gain := hp_rate * cycles + character.out_combat_hp_fraction
		if hp_gain >= float(max_hp - character.current_hp):
			character.current_hp = max_hp
			character.out_combat_hp_fraction = 0.0
		else:
			var whole_hp := int(floor(hp_gain))
			character.current_hp += whole_hp
			character.out_combat_hp_fraction = hp_gain - float(whole_hp)
	else:
		character.out_combat_hp_fraction = 0.0
	if character.current_mana < max_mana:
		var mana_gain := mana_rate * cycles + character.out_combat_mana_fraction
		if mana_gain >= float(max_mana - character.current_mana):
			character.current_mana = max_mana
			character.out_combat_mana_fraction = 0.0
		else:
			var whole_mana := int(floor(mana_gain))
			character.current_mana += whole_mana
			character.out_combat_mana_fraction = mana_gain - float(whole_mana)
	else:
		character.out_combat_mana_fraction = 0.0
	return before_hp != character.current_hp or before_mana != character.current_mana or not is_equal_approx(before_hp_fraction, character.out_combat_hp_fraction) or not is_equal_approx(before_mana_fraction, character.out_combat_mana_fraction)

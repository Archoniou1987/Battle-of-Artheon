class_name OutOfCombatRegenerationService
extends RefCounted

## Offline and online use exactly the same elapsed-time calculation.
## PAR012: extra percentage points of MaxHP per minute.
## PAR015: one flat mana bonus both per round and per 10 seconds outside combat.
## PAR013 legacy items normalize to PAR015; PAR017 remains legacy flat HP.
## Fractional progress is persisted on CharacterState (never per-frame rounded).

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
	var hp_rate := ResourceRegenerationRules.hp_per_interval(max_hp, float(totals.get("PAR012", 0.0)))
	hp_rate += maxf(0.0, float(totals.get("PAR017", 0.0))) # legacy items only
	var mana_rate := ResourceRegenerationRules.mana_per_interval(float(totals.get("PAR015", 0.0)))
	if not is_finite(hp_rate) or not is_finite(mana_rate):
		push_error("Invalid canonical resource regeneration rate")
		return false
	var before_hp := character.current_hp
	var before_mana := character.current_mana
	var before_hp_fraction := character.out_combat_hp_fraction
	var before_mana_fraction := character.out_combat_mana_fraction
	var cycles := elapsed_seconds / ResourceRegenerationRules.INTERVAL_SECONDS
	if character.current_hp < max_hp:
		var hp_gain := hp_rate * cycles + character.out_combat_hp_fraction
		if hp_gain >= float(max_hp - character.current_hp):
			character.current_hp = max_hp
			character.out_combat_hp_fraction = 0.0
		else:
			var whole_hp := int(floor(hp_gain + 0.000000001))
			character.current_hp += whole_hp
			character.out_combat_hp_fraction = maxf(0.0, hp_gain - float(whole_hp))
	else:
		character.out_combat_hp_fraction = 0.0
	if character.current_mana < max_mana:
		var mana_gain := mana_rate * cycles + character.out_combat_mana_fraction
		if mana_gain >= float(max_mana - character.current_mana):
			character.current_mana = max_mana
			character.out_combat_mana_fraction = 0.0
		else:
			var whole_mana := int(floor(mana_gain + 0.000000001))
			character.current_mana += whole_mana
			character.out_combat_mana_fraction = maxf(0.0, mana_gain - float(whole_mana))
	else:
		character.out_combat_mana_fraction = 0.0
	return before_hp != character.current_hp or before_mana != character.current_mana or not is_equal_approx(before_hp_fraction, character.out_combat_hp_fraction) or not is_equal_approx(before_mana_fraction, character.out_combat_mana_fraction)

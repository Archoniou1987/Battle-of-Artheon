class_name CombatResourceService
extends RefCounted

## Single combat-round regeneration boundary for PAR015/016.
## PAR015 uses the same flat mana bonus as out-of-combat /10sec;
## any legacy PAR013 bonus was normalized during equipment aggregation.
## Called once at the opening of each round, before actions are locked and
## before the start-of-round snapshot. Dead combatants cannot regenerate.
## Regeneration is passive resource renewal, not healing/resurrection.
static func apply_round_regeneration(state: CombatState) -> void:
	for combatant in state.combatants.values():
		if combatant == null or combatant.is_death_finalized() or combatant.hp <= 0:
			# Passive regeneration cannot rescue a combatant still lethally wounded.
			continue
		var hp_per_round := CombatModifierService.value(combatant, "hp_regen_round", state.round_number)
		var mana_per_round := CombatModifierService.value(combatant, "mana_regen_round", state.round_number)
		if not is_finite(hp_per_round) or not is_finite(mana_per_round):
			push_error("Invalid combat-round HP/mana regeneration")
			continue
		var hp_points := maxi(0, int(floor(hp_per_round)))
		var mana_gain := ResourceRegenerationRules.mana_per_interval(mana_per_round)
		if not is_finite(mana_gain) or not is_finite(combatant.mana_regen_fraction):
			push_error("Invalid configured combat mana regeneration")
			continue
		if hp_points > 0:
			combatant.restore_hp(mini(hp_points,maxi(0,combatant.max_hp-combatant.hp)))
		if combatant.mana >= combatant.max_mana:
			combatant.mana_regen_fraction = 0.0
			continue
		var accumulated: float = mana_gain + combatant.mana_regen_fraction
		var mana_points := maxi(0, int(floor(accumulated + 0.000000001)))
		combatant.mana = mini(combatant.max_mana, combatant.mana + mana_points)
		combatant.mana_regen_fraction = 0.0 if combatant.mana >= combatant.max_mana else maxf(0.0, accumulated - float(mana_points))

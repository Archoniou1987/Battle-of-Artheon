class_name CombatResourceService
extends RefCounted

## Single combat-round regeneration boundary for PAR015/016.
## PAR013 is kept separate (non-round regeneration) by design.
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
		var mana_points := maxi(0, int(floor(mana_per_round)))
		if hp_points > 0:
			combatant.restore_hp(hp_points)
		if mana_points > 0:
			combatant.mana = mini(combatant.max_mana, combatant.mana + mana_points)

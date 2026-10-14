class_name ParCombatContract
extends RefCounted

## Shared mandatory inputs for physical and magical combat. These are ratings;
## direct percentage overlays are separate and applied after RatingMatrix.
const RATINGS := {
	"PAR030":"hit_chance_rating", "PAR031":"dodge_rating", "PAR032":"anti_dodge_rating",
	"PAR033":"crit_chance_rating", "PAR034":"anti_crit_rating", "PAR035":"crit_damage_rating",
	"PAR075":"counterattack_rating", "PAR150":"magic_damage_rating"
}

static func validate(combatant: CombatantState) -> Dictionary:
	if combatant == null:
		return {"ok":false, "reason":"missing_combatant"}
	for legacy in ["STR","DEX","END","AGI","STA","INT","WIS","INTUITION","magic_hit_rating","magic_hit","magic_crit_rating","magic_damage_flat","hit","hit_modifier"]:
		if combatant.combat_stats.has(legacy):
			return {"ok":false, "reason":"obsolete_combat_stat_" + legacy}
	var totals: Variant = combatant.combat_stats.get("par_totals")
	if not totals is Dictionary:
		return {"ok":false, "reason":"missing_par_totals"}
	if not totals.has("PAR073") or not RatingMatrix._number(totals["PAR073"]):
		return {"ok":false, "reason":"missing_or_invalid_PAR073"}
	var capacity := float(totals["PAR073"])
	if capacity != floor(capacity) or capacity < 0 or capacity > 5:
		return {"ok":false, "reason":"invalid_PAR073"}
	for id in RATINGS:
		var key: String = RATINGS[id]
		if not totals.has(id) or not RatingMatrix._number(totals[id]):
			return {"ok":false, "reason":"missing_or_invalid_" + id}
		for field in [key, key + "_percent"]:
			if not combatant.combat_stats.has(field) or not RatingMatrix._number(combatant.combat_stats[field]):
				return {"ok":false, "reason":"missing_or_invalid_" + field}
		if float(combatant.combat_stats[key]) != float(totals[id]):
			return {"ok":false, "reason":"PAR_source_mismatch_" + id}
	return {"ok":true}

static func action_status(combatant: CombatantState, round_number: int) -> Dictionary:
	var checked := validate(combatant)
	if not bool(checked.ok):
		return checked
	var tempo := CombatModifierService.effective_tempo(combatant, round_number)
	if not is_finite(tempo):
		return {"ok":false, "reason":"invalid_tempo"}
	if tempo <= -100.0:
		return {"ok":false, "reason":"stunned"}
	return {"ok":true}

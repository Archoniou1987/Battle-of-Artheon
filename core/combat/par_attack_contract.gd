class_name ParAttackContract
extends RefCounted

## Mandatory ABI001 boundary shared by commands, simulation and counterattacks.
## Weapon profiles supply identity/reach only; damage comes exclusively from PAR.
static func validate(combatant: CombatantState) -> Dictionary:
	var shared := ParCombatContract.validate(combatant)
	if not bool(shared.ok):
		return shared
	var totals: Dictionary = combatant.combat_stats.get("par_totals", {})
	for id in ["PAR052", "PAR057", "PAR073"]:
		if not totals.has(id) or not (totals[id] is int or totals[id] is float) or not is_finite(float(totals[id])):
			return {"ok": false, "reason": "missing_or_invalid_" + id}
	var capacity := float(totals["PAR073"])
	if capacity != floor(capacity) or capacity < 0 or capacity > 4:
		return {"ok": false, "reason": "invalid_PAR073"}
	var count := float(totals["PAR057"])
	if count != 1.0 and count != 2.0:
		return {"ok": false, "reason": "invalid_PAR057"}
	var weapons: Array = combatant.combat_stats.get("weapon_profiles", [])
	if weapons.size() != int(count):
		return {"ok": false, "reason": "PAR057_weapon_count_mismatch"}
	var ranges: Dictionary = combatant.combat_stats.get("par_attack_ranges", {})
	var seen := {}
	var weapon_ids := {}
	for weapon in weapons:
		if not weapon is Dictionary:
			return {"ok": false, "reason": "invalid_weapon_metadata"}
		var slot := String(weapon.get("slot", ""))
		if not ["main_hand", "off_hand"].has(slot) or seen.has(slot):
			return {"ok": false, "reason": "invalid_weapon_hand_identity"}
		seen[slot] = true
		if count == 2.0 and not bool(weapon.get("is_unarmed", false)):
			var instance_id := String(weapon.get("instance_id", ""))
			if instance_id.is_empty() or weapon_ids.has(instance_id):
				return {"ok": false, "reason": "two_distinct_weapon_instances_required"}
			weapon_ids[instance_id] = true
		if slot == "off_hand" and bool(weapon.get("is_unarmed", false)):
			return {"ok":false, "reason":"off_hand_requires_weapon"}
		var id := "PAR050" if slot == "main_hand" else "PAR051"
		if not ParCalculationService.valid_damage_range(ranges.get(id)):
			return {"ok": false, "reason": "missing_or_invalid_" + id}
	if not seen.has("main_hand"):
		return {"ok": false, "reason": "missing_main_hand"}
	return {"ok": true, "count": int(count)}

static func resolve(combatant: CombatantState, profile: Dictionary) -> Dictionary:
	if int(profile.get("hit_count", 1)) != 1:
		return {"ok": false, "reason": "ABI001_requires_one_hit_per_weapon"}
	var checked := validate(combatant)
	if not bool(checked.ok):
		return checked
	var index := int(profile.get("weapon_index", -1))
	var weapons: Array = combatant.combat_stats["weapon_profiles"]
	if index < 0 or index >= weapons.size():
		return {"ok": false, "reason": "invalid_abi001_weapon_index"}
	var id := "PAR051" if String(weapons[index]["slot"]) == "off_hand" else "PAR050"
	var damage: Dictionary = combatant.combat_stats["par_attack_ranges"][id]
	var bonus := float(combatant.combat_stats["par_totals"]["PAR052"])
	var result := profile.duplicate(true)
	result["damage_min"] = float(damage["min"]) + bonus
	result["damage_max"] = float(damage["max"]) + bonus
	result["damage_type"] = String(damage["type"])
	result["source_par"] = id
	return {"ok": true, "profile": result, "source_par": id, "range": damage}

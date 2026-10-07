extends SceneTree

## Stable Combat v1 regression gate.
## Keep this runner focused on deterministic rules that later combat-v2 work must preserve
## unless a rule is intentionally superseded and its regression case is updated explicitly.

func _init() -> void:
	var balance := TestFixtureLoader.load_json("res://data/balance/physical_combat.json")
	var effect_data := TestFixtureLoader.load_json("res://data/test/effects.json")
	var effect_map := {}
	for effect in effect_data.get("effects", []):
		effect_map[String(effect.get("id", ""))] = effect
	balance["effects"] = effect_map

	var equipment_ok := EquipmentFixtureCases.run()
	var physical_ok := PhysicalAttackCases.run(balance)
	var duel_ok := DuelSmokeCases.run(balance)
	var action_ok := ActionResolverCases.run()
	var defence_ok := DeliveryDefenceCases.run(balance)
	var resist_ok := ResistEffectCases.run(balance)
	var aoe_ok := AoeCases.run(balance)
	var round_ok := RoundOrchestratorCases.run(balance)
	var group_ok := GroupCombatCases.run(balance)
	var engagement_ok := EngagementCases.run(balance)
	var group_action_ok := GroupActionPolicyCases.run()
	var opportunity_ok := OpportunityActionCases.run()
	var ok := equipment_ok and physical_ok and duel_ok and action_ok and defence_ok and resist_ok and aoe_ok and round_ok and group_ok and engagement_ok and group_action_ok and opportunity_ok

	print("COMBAT_V1_BASELINE equipment=", equipment_ok, " physical=", physical_ok, " duel=", duel_ok, " action=", action_ok, " defence=", defence_ok, " resist=", resist_ok, " aoe=", aoe_ok, " round=", round_ok, " group=", group_ok, " engagement=", engagement_ok, " group_action=", group_action_ok, " opportunity=", opportunity_ok)
	print("COMBAT_V1_REGRESSION_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

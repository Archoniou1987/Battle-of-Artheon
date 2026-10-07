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

	print("REGRESSION_START=equipment")
	var equipment_ok := EquipmentFixtureCases.run()
	print("REGRESSION_DONE=equipment ok=",equipment_ok)
	print("REGRESSION_START=physical")
	var physical_ok := PhysicalAttackCases.run(balance)
	print("REGRESSION_DONE=physical ok=",physical_ok)
	print("REGRESSION_START=duel")
	var duel_ok := DuelSmokeCases.run(balance)
	print("REGRESSION_DONE=duel ok=",duel_ok)
	print("REGRESSION_START=action")
	var action_ok := ActionResolverCases.run()
	print("REGRESSION_DONE=action ok=",action_ok)
	print("REGRESSION_START=defence")
	var defence_ok := DeliveryDefenceCases.run(balance)
	print("REGRESSION_DONE=defence ok=",defence_ok)
	print("REGRESSION_START=resist")
	var resist_ok := ResistEffectCases.run(balance)
	print("REGRESSION_DONE=resist ok=",resist_ok)
	print("REGRESSION_START=aoe")
	var aoe_ok := AoeCases.run(balance)
	print("REGRESSION_DONE=aoe ok=",aoe_ok)
	print("REGRESSION_START=round")
	var round_ok := RoundOrchestratorCases.run(balance)
	print("REGRESSION_DONE=round ok=",round_ok)
	print("REGRESSION_START=group")
	var group_ok := GroupCombatCases.run(balance)
	print("REGRESSION_DONE=group ok=",group_ok)
	print("REGRESSION_START=engagement")
	var engagement_ok := EngagementCases.run(balance)
	print("REGRESSION_DONE=engagement ok=",engagement_ok)
	print("REGRESSION_START=group_action")
	var group_action_ok := GroupActionPolicyCases.run()
	print("REGRESSION_DONE=group_action ok=",group_action_ok)
	print("REGRESSION_START=opportunity")
	var opportunity_ok := OpportunityActionCases.run()
	print("REGRESSION_DONE=opportunity ok=",opportunity_ok)
	print("REGRESSION_START=zone")
	var zone_ok := ZoneCombatCases.run()
	print("REGRESSION_DONE=zone ok=",zone_ok)
	var ok := equipment_ok and physical_ok and duel_ok and action_ok and defence_ok and resist_ok and aoe_ok and round_ok and group_ok and engagement_ok and group_action_ok and opportunity_ok and zone_ok

	print("COMBAT_V1_BASELINE equipment=", equipment_ok, " physical=", physical_ok, " duel=", duel_ok, " action=", action_ok, " defence=", defence_ok, " resist=", resist_ok, " aoe=", aoe_ok, " round=", round_ok, " group=", group_ok, " engagement=", engagement_ok, " group_action=", group_action_ok, " opportunity=", opportunity_ok, " zone=", zone_ok)
	print("COMBAT_V1_REGRESSION_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

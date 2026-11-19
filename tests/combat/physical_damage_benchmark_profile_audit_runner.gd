extends SceneTree

## Diagnostic only: do NOT invent level-40 PAR allocation or silently
## lower generator v1.2 equipment requirements to make a benchmark pass.
const LEVEL := 40
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var budget := CharacterProgression.total_earned_stat_points(LEVEL)
	var insufficient: Array[String] = []
	var examined := 0
	for raw in ItemV12InstanceFactory.PHYSICAL_ARCHETYPES:
		var archetype := String(raw)
		var hand := "2H" if ItemV12InstanceFactory.TWO_HAND_ARCHETYPES.has(archetype) else "MH"
		var item := ItemV12InstanceFactory.generate_weapon(archetype,LEVEL,"purple",202611170+examined,hand)
		if item.is_empty():
			failures.append(archetype+"_missing_item")
			continue
		var requirements: Dictionary = item.get("requirements",{})
		var minimum_points := 0
		for raw_stat in requirements:
			# Six primary stats start at one. Count only additional points
			# needed to satisfy the exact generated item requirements.
			minimum_points += maxi(0,int(requirements[raw_stat])-1)
		if minimum_points > budget:
			insufficient.append(archetype)
		print("PHYSICAL_DAMAGE_BENCHMARK_REQUIREMENTS=",archetype,
			" required_allocated=",minimum_points," level_budget=",budget,
			" feasible=",minimum_points<=budget)
		examined += 1
	if examined != ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.size():
		failures.append("not_all_archetypes_checked")
	# Known design inconsistency is a flagged result, not a fake balance pass.
	print("PHYSICAL_DAMAGE_BENCHMARK_PROFILE_AUDIT=",
		"PASS" if failures.is_empty() else "FAIL",
		" level=",LEVEL," infeasible_archetypes=",JSON.stringify(insufficient),
		" failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

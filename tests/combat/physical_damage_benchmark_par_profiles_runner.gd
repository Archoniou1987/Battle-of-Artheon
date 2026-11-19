extends SceneTree

var failures: Array[String] = []

func _check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		print("BENCHMARK_PAR_FAIL=",label)

func _initialize() -> void:
	var archetypes: Array = ItemV12InstanceFactory.PHYSICAL_ARCHETYPES
	for raw in archetypes:
		var archetype := String(raw)
		var actor := TestFixtureLoader.new_combatant("profile_actor","Profile",40,1000)
		PhysicalDamageBenchmarkParProfiles.apply(actor,archetype)
		var p := PhysicalDamageBenchmarkParProfiles.percentages(archetype)
		_check(is_equal_approx(float(actor.combat_stats["crit_chance_rating_percent"]),float(p["crit"])),archetype+"_crit")
		_check(is_equal_approx(float(actor.combat_stats["dodge_rating_percent"]),float(p["dodge"])),archetype+"_dodge")
		_check(is_equal_approx(float(actor.combat_stats["shield_auto_block_rating_percent"]),float(p["auto_block"])),archetype+"_auto_block")
		_check(is_equal_approx(float(actor.combat_stats["crit_damage_rating_percent"]),float(p["crit_power"])),archetype+"_crit_power")
		_check(is_equal_approx(float(actor.combat_stats["armour_penetration_percent"]),float(p["armour_pen"])),archetype+"_penetration")
		_check(is_equal_approx(float(Dictionary(actor.combat_stats["par_totals"]).get("PAR126",-1)),float(p["armour_pen"])),archetype+"_PAR126")
		for key in p:
			_check(float(p[key])>=0.0 and float(p[key])<=50.0,archetype+"_"+String(key)+"_bound")
	print("PHYSICAL_DAMAGE_BENCHMARK_PAR_PROFILES=","PASS" if failures.is_empty() else "FAIL"," archetypes=",archetypes.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)

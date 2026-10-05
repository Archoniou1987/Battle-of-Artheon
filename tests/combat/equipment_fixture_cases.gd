class_name EquipmentFixtureCases
extends RefCounted

## Verifies that the JSON fixtures become the intended runtime combat stats.

static func run() -> bool:
	var dagger := TestFixtureLoader.build_combatant("TEST_DAGGER_FIGHTER")
	var sword := TestFixtureLoader.build_combatant("TEST_SWORD_FIGHTER")
	var axe := TestFixtureLoader.build_combatant("TEST_AXE_FIGHTER")
	var shield := TestFixtureLoader.build_combatant("TEST_SHIELD_FIGHTER")
	if dagger == null or sword == null or axe == null or shield == null:
		return false

	return (
		dagger.hp == 100
		and is_equal_approx(float(dagger.combat_stats.get("dodge", 0.0)), 20.0)
		and int(dagger.combat_stats.get("weapon_attack_count", 0)) == 2
		and int(dagger.combat_stats.get("manual_block_zone_capacity", 0)) == 1
		and is_equal_approx(float(sword.combat_stats.get("auto_block", 0.0)), 15.0)
		and is_equal_approx(float(axe.combat_stats.get("crit", 0.0)), 15.0)
		and is_equal_approx(float(shield.armour.get("head", {}).get("piercing", 0.0)), 50.0)
		and is_equal_approx(float(shield.armour.get("legs", {}).get("blunt", 0.0)), 50.0)
		and int(shield.combat_stats.get("manual_block_zone_capacity", 0)) == 2
	)

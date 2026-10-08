class_name EquipmentFixtureCases
extends RefCounted

static func run() -> bool:
	var dagger := TestFixtureLoader.build_combatant("TEST_DAGGER_FIGHTER")
	var sword := TestFixtureLoader.build_combatant("TEST_SWORD_FIGHTER")
	var axe := TestFixtureLoader.build_combatant("TEST_AXE_FIGHTER")
	var shield := TestFixtureLoader.build_combatant("TEST_SHIELD_FIGHTER")
	var mixed := TestFixtureLoader.build_combatant("TEST_MIXED_WEAPON_FIGHTER")
	if dagger == null or sword == null or axe == null or shield == null or mixed == null: return false
	var dagger_profiles:Array=dagger.combat_stats.get("weapon_profiles",[])
	if dagger_profiles.size()!=2: return false
	var first_dagger:Dictionary=dagger_profiles[0]
	var second_dagger:Dictionary=dagger_profiles[1]
	var mixed_profiles:Array=mixed.combat_stats.get("weapon_profiles",[])
	if mixed_profiles.size()!=2: return false
	var mixed_first:Dictionary=mixed_profiles[0]
	var mixed_second:Dictionary=mixed_profiles[1]
	return (
		String(mixed_first.get("item_id",""))=="TEST_DAGGER"
		and String(mixed_first.get("damage_type",""))=="piercing"
		and is_equal_approx(float(mixed_first.get("damage_min",0.0)),2.0)
		and is_equal_approx(float(mixed_first.get("damage_max",0.0)),3.0)
		and String(mixed_second.get("item_id",""))=="TEST_AXE"
		and String(mixed_second.get("damage_type",""))=="chopping"
		and is_equal_approx(float(mixed_second.get("damage_min",0.0)),4.0)
		and is_equal_approx(float(mixed_second.get("damage_max",0.0)),5.0)
		and 		String(first_dagger.get("item_id",""))=="TEST_DAGGER"
		and String(second_dagger.get("item_id",""))=="TEST_DAGGER"
		and is_equal_approx(float(first_dagger.get("damage_min",0.0)),2.0)
		and is_equal_approx(float(second_dagger.get("damage_max",0.0)),3.0)
		and dagger.hp == 100
		and is_equal_approx(float(dagger.combat_stats.get("dodge",0.0)),15.0)
		and int(dagger.combat_stats.get("weapon_attack_count",0)) == 2
		and int(dagger.combat_stats.get("manual_block_zone_capacity",0)) == 1
		and is_equal_approx(float(sword.combat_stats.get("auto_block",0.0)),15.0)
		and is_equal_approx(float(sword.combat_stats.get("anti_dodge",0.0)),5.0)
		and is_equal_approx(float(axe.combat_stats.get("crit",0.0)),10.0)
		and is_equal_approx(float(shield.armour.get("head",{}).get("piercing",0.0)),15.0)
		and is_equal_approx(float(shield.armour.get("legs",{}).get("blunt",0.0)),15.0)
		and int(shield.combat_stats.get("manual_block_zone_capacity",0)) == 2
		and not shield.combat_stats.has("manual_block_zone_count")
		and is_equal_approx(float(shield.combat_stats.get("auto_block",0.0)),0.0)
	)

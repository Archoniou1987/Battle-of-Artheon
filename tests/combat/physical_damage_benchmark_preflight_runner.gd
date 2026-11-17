extends SceneTree

## Preparatory gate for the agreed level-40, one-target damage benchmark.
## This is deliberately NOT the 1000-fight simulator. Do not report any
## damage numbers until a dedicated simulation has been validated.
const LEVEL := 40
const DUMMY_HP := 10000
const BATTLES_PER_ARCHETYPE := 1000
const HIT_PCT := 95.0
const MAX_CRIT_PCT := 40.0
const MAX_DODGE_PCT := 40.0
const MAX_AUTO_BLOCK_PCT := 40.0
const MAX_ARMOUR_PEN_PCT := 25.0
const CRIT_ARCHETYPE_EXTRA_POWER_PCT := 50.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("PHYSICAL_DAMAGE_PREFLIGHT_FAIL=", label)

func _verify() -> void:
	var rules_variant: Variant = JSON.parse_string(FileAccess.get_file_as_string(ItemTemplateGeneratorV12.RULE_PATH))
	_check(rules_variant is Dictionary, "generator_v12_rules_parse")
	if not rules_variant is Dictionary:
		_finish()
		return
	var rules: Dictionary = rules_variant
	var archetype_rows: Dictionary = {}
	for raw in rules.get("weapon_archetypes", []):
		if not raw is Dictionary:
			continue
		var definition: Dictionary = raw
		archetype_rows[String(definition.get("id", ""))] = definition
	var ability_definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	var missing_abilities: Array[String] = []
	var archetypes_verified := 0
	for archetype_id in ItemV12InstanceFactory.PHYSICAL_ARCHETYPES:
		var archetype := String(archetype_id)
		_check(archetype_rows.has(archetype), archetype + "_canonical_rule")
		if not archetype_rows.has(archetype):
			continue
		var definition: Dictionary = archetype_rows[archetype]
		var abilities: Array = definition.get("abilities", [])
		_check(abilities.size() == 4, archetype + "_four_abi")
		for raw_id in abilities:
			var abi_id := String(raw_id)
			if not ability_definitions.has(abi_id) or not AbilityCatalog.is_executable_id(abi_id):
				missing_abilities.append(abi_id)
		var hero := CharacterState.new("BENCH_" + archetype, archetype, LEVEL)
		for primary in ["PAR001", "PAR002", "PAR003", "PAR004", "PAR005", "PAR006"]:
			hero.progression.base_stats[primary] = 90
		var repository := ItemRepository.new()
		var two_hand := ItemV12InstanceFactory.TWO_HAND_ARCHETYPES.has(archetype)
		var item := ItemV12InstanceFactory.grant_weapon(hero, repository, archetype, LEVEL, "purple", 202611170 + archetypes_verified, "2H" if two_hand else "MH")
		_check(not item.is_empty(), archetype + "_level40_item")
		if item.is_empty():
			continue
		_check(item.get("abilities", []) == abilities, archetype + "_abi_links")
		_check(hero.equip("main_hand", String(item["instance_id"]), repository), archetype + "_equip")
		var fighter := CharacterCombatBuilder.build(hero, repository, {"health": DUMMY_HP})
		_check(fighter != null, archetype + "_canonical_combatant")
		if fighter != null:
			_check(WeaponAttackProfile.all(fighter).size() > 0, archetype + "_attack_profiles")
		archetypes_verified += 1
	_check(missing_abilities.is_empty(), "all_abilities_executable_" + ",".join(missing_abilities))
	_check(LEVEL == 40 and DUMMY_HP == 10000 and BATTLES_PER_ARCHETYPE == 1000, "fixed_benchmark_scenario")
	_check(HIT_PCT == 95.0 and MAX_CRIT_PCT == 40.0 and MAX_DODGE_PCT == 40.0 and MAX_AUTO_BLOCK_PCT == 40.0 and MAX_ARMOUR_PEN_PCT == 25.0, "approved_rating_caps")
	_check(CRIT_ARCHETYPE_EXTRA_POWER_PCT == 50.0, "approved_crit_specialist_bonus")
	print("PHYSICAL_DAMAGE_PREFLIGHT_ARCHETYPES=", archetypes_verified, " expected=", ItemV12InstanceFactory.PHYSICAL_ARCHETYPES.size())
	_finish()

func _finish() -> void:
	print("PHYSICAL_DAMAGE_PREFLIGHT=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

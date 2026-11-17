class_name PhysicalDamageBenchmarkFixture
extends RefCounted

## Benchmark-only input boundary. The real v1.2 weapon owns damage and ABI IDs;
## the generator's random PAR affixes NEVER enter the combat snapshot.
const HERO_HP := 2000
const DUMMY_DAMAGE_MIN := 1.0
const DUMMY_DAMAGE_MAX := 5.0

static func create_weapon(hero: CharacterState, repo: ItemRepository, archetype: String, level: int, seed: int) -> Dictionary:
	var hand := "2H" if ItemV12InstanceFactory.TWO_HAND_ARCHETYPES.has(archetype) else "MH"
	var item := ItemV12InstanceFactory.generate_weapon(archetype,level,"purple",seed,hand)
	if item.is_empty():
		return {}
	# Ignore random rarity/CORE PAR and level equipment requirements ONLY in
	# this test item; actual generator, saved items and game rules are untouched.
	item["par_bonuses"]={}
	item["requirements"]={}
	item["v12_core_rolls"]=[]
	item["v12_rarity_rolls"]=[]
	if not repo.add_item(item):
		return {}
	if not hero.receive_item(String(item["instance_id"]),repo):
		return {}
	if not hero.equip("main_hand",String(item["instance_id"]),repo):
		return {}
	return item

static func prepare_actor(actor: CombatantState, archetype: String, weapon: Dictionary) -> void:
	PhysicalDamageBenchmarkParProfiles.apply(actor,archetype)
	actor.max_hp=HERO_HP
	actor.hp=HERO_HP
	# ABI damage reads PAR232. Remove all unrequested STR/AP sources so
	# weapon-vs-ABI measurements aren't inflated by a synthetic character.
	var totals: Dictionary = actor.combat_stats.get("par_totals",{}).duplicate(true)
	totals["PAR232"]=0.0
	totals["PAR052"]=0.0
	actor.combat_stats["par_totals"]=totals
	actor.stats["PAR232"]=0.0
	actor.stats["PAR052"]=0.0
	# The ordinary MH range is precisely the generated item's own range,
	# without character primary-derived damage modifiers.
	var damage: Dictionary = weapon.get("damage",{})
	var minimum := float(damage.get("min",0.0))
	var maximum := float(damage.get("max",0.0))
	var profiles: Array = actor.combat_stats.get("weapon_profiles",[])
	for idx in range(profiles.size()):
		var profile: Dictionary = profiles[idx]
		if int(profile.get("weapon_index",idx))>0 or String(profile.get("slot",""))=="off_hand":
			continue
		profile["damage_min"]=minimum
		profile["damage_max"]=maximum
		var attack_profiles: Array = profile.get("attack_profiles",[])
		for j in range(attack_profiles.size()):
			var attack: Dictionary = attack_profiles[j]
			attack["damage_min"]=minimum
			attack["damage_max"]=maximum
			attack_profiles[j]=attack
		profile["attack_profiles"]=attack_profiles
		profiles[idx]=profile
	actor.combat_stats["weapon_profiles"]=profiles
	var attack_ranges: Dictionary = actor.combat_stats.get("par_attack_ranges",{}).duplicate(true)
	if attack_ranges.has("PAR050"):
		var range_data: Dictionary = attack_ranges["PAR050"]
		range_data["min"]=minimum
		range_data["max"]=maximum
		attack_ranges["PAR050"]=range_data
	actor.combat_stats["par_attack_ranges"]=attack_ranges

static func prepare_dummy(dummy: CombatantState) -> void:
	dummy.level=40
	dummy.combat_stats["dodge_rating_percent"]=0.0
	dummy.combat_stats["shield_auto_block_rating_percent"]=0.0
	dummy.combat_stats["anti_crit_rating_percent"]=0.0
	dummy.combat_loadout["can_auto_block"]=false
	dummy.combat_stats.erase("manual_block_zones")
	# The dummy performs ordinary canonical attacks, not ABI. It can trigger
	# dodge/block/crit-on-defence mechanics without dominating the fight.
	var profiles: Array = dummy.combat_stats.get("weapon_profiles",[])
	for idx in range(profiles.size()):
		var profile: Dictionary = profiles[idx]
		profile["damage_min"]=DUMMY_DAMAGE_MIN
		profile["damage_max"]=DUMMY_DAMAGE_MAX
		var attacks: Array = profile.get("attack_profiles",[])
		for j in range(attacks.size()):
			var attack: Dictionary = attacks[j]
			attack["damage_min"]=DUMMY_DAMAGE_MIN
			attack["damage_max"]=DUMMY_DAMAGE_MAX
			attacks[j]=attack
		profile["attack_profiles"]=attacks
		profiles[idx]=profile
	dummy.combat_stats["weapon_profiles"]=profiles

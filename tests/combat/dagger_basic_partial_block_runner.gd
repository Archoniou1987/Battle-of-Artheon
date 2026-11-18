extends SceneTree

## Regression: ordinary dual-dagger attacks share ABI's 50% block damage,
## while other weapons still stop on successful manual/auto block.
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("DAGGER_BLOCK_FAIL=", label)

func _attack(session: ArenaCombatSession, auto: bool = false) -> CombatEvent:
	var target := session.fighter(false)
	target.max_hp = 10000
	target.hp = 10000
	target.combat_stats["dodge_rating_percent"] = 0.0
	target.combat_stats["anti_crit_rating_percent"] = 0.0
	target.combat_loadout["can_manual_block"] = true
	target.combat_loadout["can_auto_block"] = true
	target.combat_stats["manual_block_zones"] = [] if auto else ["head"]
	target.combat_stats["shield_auto_block_rating_percent"] = 100.0 if auto else 0.0
	var event := session.state.create_event(CombatEvent.Kind.ATTACK,session.player_id,ArenaCombatSession.ENEMY_ID,{
		"zone":"head", "damage_type":"piercing", "raw_damage":100.0,
		"is_weapon_attack":true, "weapon_index":0, "source_kind":"weapon",
		"hit_already_resolved":true,
		"rolls":{"hit":1,"dodge":100,"auto_block":1,"block_crush":100,"crit":100,"damage":0.5}
	})
	session.engine.resolve_event(event)
	session.engine.resolve_pending_events()
	return event

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var character := CharacterState.new("DAGGER_BLOCK_HERO","Dagger Tester",40)
	character.progression.level = 40
	character.level = 40
	var repository := ItemRepository.new()
	var dagger := PhysicalDamageBenchmarkFixture.create_weapon(character,repository,"DAGGER_ATTACK",40,202611181)
	_check(not dagger.is_empty(),"real_dagger_generated")
	if dagger.is_empty():
		_finish()
		return
	var session := ArenaCombatSession.new(character,repository)
	var attacker := session.fighter(true)
	var defender := session.fighter(false)
	_check(attacker!=null and defender!=null,"combatants")
	if attacker==null or defender==null:
		_finish()
		return
	# Hit chance and combat context are canonical; only dice are deterministic.
	var profiles: Array = attacker.combat_stats.get("weapon_profiles",[])
	_check(not profiles.is_empty() and String(Dictionary(profiles[0]).get("weapon_class",""))=="dagger","real_weapon_class")
	if profiles.is_empty():
		_finish()
		return
	var manual := _attack(session)
	_check(String(manual.result.get("partial_block",""))=="manual_block","dagger_manual_partial")
	_check(is_equal_approx(float(manual.result.get("block_damage_multiplier",0)),0.5),"dagger_manual_half")
	_check(defender.hp < 10000,"dagger_manual_damage")
	var auto := _attack(session,true)
	_check(String(auto.result.get("partial_block",""))=="auto_block","dagger_auto_partial")
	_check(is_equal_approx(float(auto.result.get("block_damage_multiplier",0)),0.5),"dagger_auto_half")
	_check(defender.hp < 10000,"dagger_auto_damage")
	# A non-dagger weapon remains fully blockable even when damage_type=piercing.
	var saved := String(Dictionary(profiles[0]).get("weapon_class",""))
	var modified: Dictionary = profiles[0]
	modified["weapon_class"]="spear"
	profiles[0]=modified
	attacker.combat_stats["weapon_profiles"]=profiles
	var blocked := _attack(session)
	_check(String(blocked.result.get("outcome",""))=="manual_block","other_weapon_still_blocked")
	_check(defender.hp==10000,"other_weapon_no_blocked_damage")
	modified["weapon_class"]=saved
	profiles[0]=modified
	attacker.combat_stats["weapon_profiles"]=profiles
	_finish()

func _finish() -> void:
	print("DAGGER_BASIC_PARTIAL_BLOCK=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

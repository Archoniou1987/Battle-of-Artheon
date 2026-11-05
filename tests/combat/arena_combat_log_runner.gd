extends SceneTree

## Journal projection must follow ABI parentage, not merely ABI IDs copied into
## damage payloads, and must never count a projectile ABI as a physical strike.
func _init() -> void:
	var success: bool = _test_event_ancestry() and _test_heal_cleanse_and_miss() and _test_dagger_crit_and_flurry_hits()
	print("ARENA_COMBAT_LOG_TEST=", "PASS" if success else "FAIL")
	quit(0 if success else 1)

static func _test_catalog() -> Dictionary:
	# Pure event-log fixtures. These IDs never exist in production catalog.
	var definitions := AbilityCatalog.load_json("res://data/abilities/catalog.json")
	definitions["TEST_LOG_MAGIC"] = {"name":"Тест магии"}
	definitions["TEST_LOG_HEAL"] = {"name":"Тест лечения"}
	return definitions

func _test_event_ancestry() -> bool:
	var state := CombatState.new()
	state.begin_round()
	var cast := state.create_event(CombatEvent.Kind.ACTION,"hero","enemy",{"source_kind":"ability","ability_id":"TEST_LOG_MAGIC"})
	cast.set_result("outcome","dispatched")
	var projectile := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"source_kind":"ability","ability_id":"TEST_LOG_MAGIC"},cast.event_id)
	projectile.set_result("outcome","connected")
	var spell_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"ability_id":"TEST_LOG_MAGIC","amount":23.0},projectile.event_id)
	spell_damage.set_result("hp_removed",23)
	var ignite := state.create_event(CombatEvent.Kind.EFFECT,"hero","enemy",{"effect_id":"EFF003","ability_id":"TEST_LOG_MAGIC"},cast.event_id)
	ignite.set_result("resolved",true)
	var blade := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"is_weapon_attack":true,"zone":"arms"})
	blade.set_result("outcome","connected")
	var blade_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"amount":7.0},blade.event_id)
	blade_damage.set_result("hp_removed",7)
	var dot := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"source":"effect","effect_id":"EFF003"})
	dot.set_result("hp_removed",3)
	for event in [cast,projectile,spell_damage,ignite,blade,blade_damage,dot]:
		state.record_event(event)
	var logs: Array[String] = ArenaCombatLog.lines_for_round(state.event_log,1,"hero",_test_catalog())
	if logs.size()!=3:
		print("ARENA_LOG_ANCESTRY_BAD_COUNT=",logs)
		return false
	var spell_line: String = logs[0]
	var weapon_line: String = logs[1]
	var tick_line: String = logs[2]
	var good: bool = spell_line.contains("ABI «Тест магии»") and spell_line.contains("23 урона") and spell_line.contains("EFF003")
	good = good and weapon_line.contains("руки") and weapon_line.contains("7 урона") and not weapon_line.contains("Тест магии")
	good = good and tick_line.contains("EFF003") and tick_line.contains("3 урона")
	if not good:
		print("ARENA_LOG_ANCESTRY_WRONG=",logs)
	return good

func _test_heal_cleanse_and_miss() -> bool:
	var state := CombatState.new()
	state.begin_round()
	var heal := state.create_event(CombatEvent.Kind.ACTION,"hero","hero",{"source_kind":"ability","ability_id":"TEST_LOG_HEAL"})
	heal.set_result("outcome","dispatched")
	var heal_child := state.create_event(CombatEvent.Kind.EFFECT,"hero","hero",{"inline_heal":40,"ability_id":"TEST_LOG_HEAL"},heal.event_id)
	heal_child.set_result("healed",40)
	var hot_child := state.create_event(CombatEvent.Kind.EFFECT,"hero","hero",{"effect_id":"EFF004","ability_id":"TEST_LOG_HEAL"},heal.event_id)
	hot_child.set_result("resolved",true)
	var cleanse := state.create_event(CombatEvent.Kind.ACTION,"hero","enemy",{"source_kind":"ability","ability_id":"ABI_CLEANSE"})
	cleanse.set_result("outcome","dispatched")
	var dispel := state.create_event(CombatEvent.Kind.EFFECT,"hero","enemy",{"dispel_polarity":"BUFF","ability_id":"ABI_CLEANSE"},cleanse.event_id)
	dispel.set_result("resolved",true)
	dispel.set_result("removed_effect_ids",["EFF004"])
	var failed := state.create_event(CombatEvent.Kind.ACTION,"enemy","hero",{"source_kind":"ability","ability_id":"TEST_LOG_MAGIC"})
	failed.set_result("outcome","magic_miss")
	for event in [heal,heal_child,hot_child,cleanse,dispel,failed]:
		state.record_event(event)
	var logs: Array[String] = ArenaCombatLog.lines_for_round(state.event_log,1,"hero",_test_catalog())
	var good: bool = logs.size()==3
	if good:
		good = logs[0].contains("+40 HP") and logs[0].contains("EFF004")
		good = good and logs[1].contains("снят") and logs[1].contains("EFF004")
		good = good and logs[2].contains("Противник") and logs[2].contains("промах")
	if not good:
		print("ARENA_LOG_SUPPORT_WRONG=",logs)
	return good

## Verify physical ability crit annotation and ABI406's individual resolved hits.
func _test_dagger_crit_and_flurry_hits() -> bool:
	var state := CombatState.new()
	state.begin_round()
	var flurry := state.create_event(CombatEvent.Kind.ACTION,"hero","enemy",{"source_kind":"ability","ability_id":"ABI406"})
	flurry.set_result("outcome","dispatched")
	var first := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"dagger_abi_id":"ABI406","dagger_strike_index":0,"zone":"chest"},flurry.event_id)
	first.set_result("outcome","connected")
	first.set_result("critical",true)
	var first_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"amount":87.0},first.event_id)
	first_damage.set_result("hp_removed",87)
	var second := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"dagger_abi_id":"ABI406","dagger_strike_index":1,"zone":"waist"},flurry.event_id)
	second.set_result("outcome","dodge")
	var third := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"dagger_abi_id":"ABI406","dagger_strike_index":2,"zone":"arms"},flurry.event_id)
	third.set_result("outcome","connected")
	third.set_result("critical",false)
	var third_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"amount":40.0},third.event_id)
	third_damage.set_result("hp_removed",40)
	var single := state.create_event(CombatEvent.Kind.ACTION,"hero","enemy",{"source_kind":"ability","ability_id":"ABI405"})
	single.set_result("outcome","dispatched")
	var single_hit := state.create_event(CombatEvent.Kind.ATTACK,"hero","enemy",{"dagger_abi_id":"ABI405","zone":"chest"},single.event_id)
	single_hit.set_result("outcome","connected")
	single_hit.set_result("critical",true)
	var single_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","enemy",{"amount":90.0},single_hit.event_id)
	single_damage.set_result("hp_removed",90)
	for event in [flurry,first,first_damage,second,third,third_damage,single,single_hit,single_damage]:
		state.record_event(event)
	var logs := ArenaCombatLog.lines_for_round(state.event_log,1,"hero",_test_catalog())
	var good := logs.size() == 5
	if good:
		good = logs[0].contains("127 урона") and logs[1].contains("Удар 1 (MH") and logs[1].contains("87 урона (крит)")
		good = good and logs[2].contains("Удар 2 (OH") and logs[2].contains("уклонение")
		good = good and logs[3].contains("Удар 3 (MH") and logs[3].contains("40 урона") and not logs[3].contains("крит")
		good = good and logs[4].contains("90 урона") and logs[4].contains("крит: 1/1")
	if not good:
		print("ARENA_DAGGER_HIT_LOG_WRONG=",logs)
	return good

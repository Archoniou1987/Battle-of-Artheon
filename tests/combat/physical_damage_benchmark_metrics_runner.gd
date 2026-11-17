extends SceneTree

## Attribution contract, including overkill: Combat Engine's final_damage
## is authoritative, never hp_removed nor a separately recomputed formula.
var errors: Array[String] = []

func _assert(condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)
		print("BENCH_METRICS_FAIL=",label)

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var state := CombatState.new()
	state.begin_round()
	var mh := state.create_event(CombatEvent.Kind.ATTACK,"hero","dummy",{
		"is_weapon_attack":true,"weapon_index":0})
	mh.result = {"outcome":"connected"}
	state.record_event(mh)
	var mh_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","dummy",
		{"amount":80.0},mh.event_id)
	mh_damage.result = {"final_damage":80,"hp_removed":50}
	state.record_event(mh_damage)
	var oh := state.create_event(CombatEvent.Kind.ATTACK,"hero","dummy",{
		"is_weapon_attack":true,"weapon_index":1})
	oh.result = {"outcome":"connected"}
	state.record_event(oh)
	var oh_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","dummy",
		{"amount":20.0},oh.event_id)
	oh_damage.result = {"final_damage":20,"hp_removed":20}
	state.record_event(oh_damage)
	var abi_action := state.create_event(CombatEvent.Kind.ACTION,"hero","dummy",
		{"ability_id":"ABI307"})
	state.record_event(abi_action)
	var abi_attack := state.create_event(CombatEvent.Kind.ATTACK,"hero","dummy",
		{"source_kind":"ability"},abi_action.event_id)
	state.record_event(abi_attack)
	var abi_damage := state.create_event(CombatEvent.Kind.DAMAGE,"hero","dummy",
		{"amount":120.0},abi_attack.event_id)
	abi_damage.result = {"final_damage":120,"hp_removed":10}
	state.record_event(abi_damage)
	var periodic := state.create_event(CombatEvent.Kind.DAMAGE,"hero","dummy",
		{"source":"effect","effect_id":"EFF501","amount":15.0})
	periodic.result = {"final_damage":15,"hp_removed":15}
	state.record_event(periodic)
	var other := state.create_event(CombatEvent.Kind.DAMAGE,"other","dummy",
		{"amount":999.0})
	other.result = {"final_damage":999}
	state.record_event(other)
	var result := PhysicalDamageBenchmarkMetrics.collect(state.event_log,"hero","dummy")
	_assert(int(result["total_damage"])==235,"total_without_other_source")
	_assert(int(result["mh"]["damage"])==80 and int(result["mh"]["hits"])==1,"mh_overkill_counted")
	_assert(int(result["oh"]["damage"])==20 and int(result["oh"]["hits"])==1,"oh_separate")
	_assert(int(result["abi_damage"].get("ABI307",0))==120,"abi_parent_lineage")
	_assert(int(result["dot_damage"].get("EFF501",0))==15,"dot_separate")
	print("PHYSICAL_DAMAGE_BENCHMARK_METRICS=", "PASS" if errors.is_empty() else "FAIL", " errors=",errors)
	quit(0 if errors.is_empty() else 1)

extends SceneTree

var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("BENCHMARK_POLICY_FAIL=",label)

func _initialize() -> void:
	var abilities := ["GAIN","COST_A","COST_B","COST_C"]
	var definitions := {
		"GAIN":{"ap_gain":1,"ap_cost":0},
		"COST_A":{"ap_gain":0,"ap_cost":2},
		"COST_B":{"ap_gain":0,"ap_cost":3},
		"COST_C":{"ap_gain":0,"ap_cost":5}
	}
	var first := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,{},1,0,8,0)
	_check(String(first.get("id",""))=="GAIN","generator_first")
	var gain_cd := {"GAIN":3}
	var spend_a := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,gain_cd,2,5,8,0)
	_check(String(spend_a.get("id",""))=="COST_A" and int(spend_a.get("cursor",-1))==1,"first_spender")
	var spend_b := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,gain_cd,2,5,8,1)
	_check(String(spend_b.get("id",""))=="COST_B" and int(spend_b.get("cursor",-1))==2,"second_spender")
	var spend_c := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,gain_cd,2,5,8,2)
	_check(String(spend_c.get("id",""))=="COST_C" and int(spend_c.get("cursor",-1))==0,"third_spender")
	var no_ap := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,gain_cd,2,0,8,2)
	_check(String(no_ap.get("id","")).is_empty(),"no_ap_no_cast")
	var cooldown := {"GAIN":3,"COST_A":8,"COST_B":8,"COST_C":8}
	var none := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,cooldown,2,8,8,0)
	_check(String(none.get("id","")).is_empty(),"cooldown_enforced")
	var gain_after_cd := PhysicalDamageBenchmarkPolicy.choose(abilities,definitions,{},4,7,8,1)
	_check(String(gain_after_cd.get("id",""))=="GAIN","generator_by_cooldown")
	print("PHYSICAL_DAMAGE_BENCHMARK_POLICY=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

extends SceneTree

## Fast isolated verification of benchmark choice policy. Never alters Combat Engine.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ids := ["ABI301","ABI302","ABI303","ABI304"]
	var defs := {
		"ABI301":{"ap_cost":0,"ap_gain":1},
		"ABI302":{"ap_cost":2},
		"ABI303":{"ap_cost":2},
		"ABI304":{"ap_cost":5}
	}
	var cooldowns := {"ABI301":99}
	var cursor := 0
	for expected in ["ABI302","ABI303"]:
		var result := PhysicalDamageBenchmarkPolicy.choose(ids,defs,cooldowns,1,5,8,cursor)
		if String(result.get("id",""))!=expected:
			push_error("Expected "+expected+", got "+str(result))
			quit(1)
			return
		cursor=int(result["cursor"])
	for ap in [0,2,3,4]:
		var result := PhysicalDamageBenchmarkPolicy.choose(ids,defs,cooldowns,1,ap,8,cursor)
		if String(result.get("id",""))!="" or String(result.get("waiting_for",""))!="ABI304" or int(result["cursor"])!=cursor:
			push_error("Spender skipped ABI304 when AP="+str(ap)+": "+str(result))
			quit(1)
			return
	var finisher := PhysicalDamageBenchmarkPolicy.choose(ids,defs,cooldowns,1,5,8,cursor)
	if String(finisher.get("id",""))!="ABI304" or int(finisher.get("cursor",-1))!=0:
		push_error("Wrong finisher order: "+str(finisher))
		quit(1)
		return
	var regen := PhysicalDamageBenchmarkPolicy.choose(ids,defs,{},1,3,8,cursor)
	if String(regen.get("id",""))!="ABI301" or int(regen.get("cursor",-1))!=cursor:
		push_error("Generator did not preserve spend cursor: "+str(regen))
		quit(1)
		return
	var mixed := ["ABI605","ABI606","ABI607","ABI608"]
	var mixed_defs := {
		"ABI605":{"ap_cost":0,"ap_gain":1},
		"ABI606":{"ap_cost":2},
		"ABI607":{"ap_cost":3,"ap_gain":3},
		"ABI608":{"ap_cost":5}
	}
	var third := PhysicalDamageBenchmarkPolicy.choose(mixed,mixed_defs,{"ABI605":99},1,5,8,1)
	if String(third.get("id",""))!="ABI607" or int(third.get("cursor",-1))!=2:
		push_error("ABI607 must be a spender despite its AP refund: "+str(third))
		quit(1)
		return
	print("PHYSICAL_DAMAGE_ABI_ROTATION_SMOKE=PASS")
	quit(0)

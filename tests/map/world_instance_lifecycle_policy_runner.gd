extends SceneTree

func _initialize() -> void:
	var ok := true
	var solo := WorldInstanceLifecyclePolicy.solo_after_new_expedition(100)
	ok = ok and String(solo["lifecycle"])=="closed" and bool(solo["discard_world"])
	var idle := WorldInstanceLifecyclePolicy.multiplayer_next("active",0,-1,-1,100)
	ok = ok and bool(idle.get("ok",false)) and String(idle["lifecycle"])=="idle"
	var before_hour := WorldInstanceLifecyclePolicy.multiplayer_next("idle",0,100,-1,3699)
	ok = ok and String(before_hour.get("lifecycle",""))=="idle"
	var closed := WorldInstanceLifecyclePolicy.multiplayer_next("idle",0,100,-1,3700)
	ok = ok and String(closed.get("lifecycle",""))=="closed" and bool(closed.get("discard_world",false))
	var renewed := WorldInstanceLifecyclePolicy.multiplayer_next("idle",1,100,-1,500)
	ok = ok and String(renewed.get("lifecycle",""))=="active" and int(renewed.get("empty_since_unix",0))==-1
	var again := WorldInstanceLifecyclePolicy.multiplayer_next("active",0,-1,-1,550)
	ok = ok and String(again.get("lifecycle",""))=="idle" and int(again.get("empty_since_unix",-1))==550
	var rejected_archive := WorldInstanceLifecyclePolicy.multiplayer_next("archived",0,100,-1,4000)
	ok = ok and not bool(rejected_archive.get("ok",true))
	var hold := WorldInstanceLifecyclePolicy.multiplayer_effective_occupancy(0,1)
	ok = ok and bool(hold.get("ok",false)) and int(hold.get("occupants",-1))==1
	var still_active := WorldInstanceLifecyclePolicy.multiplayer_next("active",int(hold["occupants"]),-1,-1,900)
	ok = ok and String(still_active.get("lifecycle",""))=="active"
	var nobody := WorldInstanceLifecyclePolicy.multiplayer_effective_occupancy(0,0)
	var idle_after_combat := WorldInstanceLifecyclePolicy.multiplayer_next("active",int(nobody["occupants"]),-1,-1,910)
	ok = ok and String(idle_after_combat.get("lifecycle",""))=="idle"
	var town := WorldInstanceLifecyclePolicy.multiplayer_reconnect("closed",false)
	ok = ok and bool(town.get("ok",false)) and String(town.get("destination",""))=="town" and not bool(town.get("equipment_penalty",true))
	var battle := WorldInstanceLifecyclePolicy.multiplayer_reconnect("active",true)
	ok = ok and bool(battle.get("ok",false)) and String(battle.get("destination",""))=="battle"
	var forbidden := WorldInstanceLifecyclePolicy.multiplayer_reconnect("closed",true)
	ok = ok and not bool(forbidden.get("ok",true))
	print("WORLD_INSTANCE_LIFECYCLE_POLICY_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

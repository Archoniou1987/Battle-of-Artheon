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
	print("WORLD_INSTANCE_LIFECYCLE_POLICY_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

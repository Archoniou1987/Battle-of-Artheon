extends SceneTree

func _initialize() -> void:
	var ok := true
	var solo := WorldInstanceLifecyclePolicy.solo_after_new_expedition(100)
	ok = ok and int(solo["expires_at_unix"])==3700
	# Solo has no idle phase based on absence of the owner.
	var active := WorldInstanceLifecyclePolicy.multiplayer_next("active",0,-1,-1,100)
	ok = ok and bool(active.get("ok",false)) and String(active["lifecycle"])=="idle"
	var before_hour := WorldInstanceLifecyclePolicy.multiplayer_next("idle",0,100,-1,3699)
	ok = ok and String(before_hour.get("lifecycle",""))=="idle"
	var archived := WorldInstanceLifecyclePolicy.multiplayer_next("idle",0,100,-1,3700)
	ok = ok and String(archived.get("lifecycle",""))=="archived" and int(archived.get("archived_at_unix",-1))==3700
	var before_purge := WorldInstanceLifecyclePolicy.multiplayer_next("archived",0,100,3700,7299)
	ok = ok and String(before_purge.get("lifecycle",""))=="archived"
	var purged := WorldInstanceLifecyclePolicy.multiplayer_next("archived",0,100,3700,7300)
	ok = ok and String(purged.get("lifecycle",""))=="closed"
	var reopened := WorldInstanceLifecyclePolicy.multiplayer_next("idle",1,100,-1,500)
	ok = ok and String(reopened.get("lifecycle",""))=="active" and int(reopened.get("empty_since_unix",0))==-1
	var again := WorldInstanceLifecyclePolicy.multiplayer_next("active",0,-1,-1,550)
	ok = ok and String(again.get("lifecycle",""))=="idle" and int(again.get("empty_since_unix",-1))==550
	var archive_join := WorldInstanceLifecyclePolicy.multiplayer_next("archived",1,100,3700,4000)
	ok = ok and bool(archive_join.get("requires_restore",false)) and String(archive_join.get("lifecycle",""))=="archived"
	var invalid := WorldInstanceLifecyclePolicy.multiplayer_next("idle",0,-1,-1,500)
	ok = ok and not bool(invalid.get("ok",true))
	print("WORLD_INSTANCE_LIFECYCLE_POLICY_TEST="+("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)

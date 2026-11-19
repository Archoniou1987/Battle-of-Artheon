class_name PhysicalDamageBenchmarkMetrics
extends RefCounted

## Read-only reporting over canonical CombatEvent results.
## Never estimates damage from MH, ABI catalog values, or HP lost.
static func collect(events: Array[CombatEvent], source_id: String, target_id: String) -> Dictionary:
	var by_id: Dictionary = {}
	for event in events:
		by_id[event.event_id] = event
	var weapon_mh := {"damage":0, "hits":0, "attempts":0}
	var weapon_oh := {"damage":0, "hits":0, "attempts":0}
	var abi: Dictionary = {}
	var dot: Dictionary = {}
	var dot_ticks: Dictionary = {}
	var total := 0
	var unattributed := 0
	for event in events:
		if event.source_id != source_id or event.target_id != target_id:
			continue
		if event.kind == CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)):
			var bucket: Dictionary = weapon_oh if int(event.payload.get("weapon_index",0)) > 0 else weapon_mh
			bucket["attempts"] = int(bucket["attempts"]) + 1
			if String(event.result.get("outcome","")) == "connected":
				bucket["hits"] = int(bucket["hits"]) + 1
		if event.kind != CombatEvent.Kind.DAMAGE:
			continue
		var dealt := maxi(0,int(event.result.get("final_damage",0)))
		# final_damage is post-mitigation and can exceed remaining target HP.
		total += dealt
		if String(event.payload.get("source","")) == "effect":
			var effect_id := String(event.payload.get("effect_id","UNKNOWN_EFF"))
			dot[effect_id] = int(dot.get(effect_id,0)) + dealt
			dot_ticks[effect_id] = int(dot_ticks.get(effect_id,0)) + 1
			continue
		# For reaction/counterattack damage, the direct ATTACK parent identifies
		# the ABI. Its ancestor may be the *opponent's* blocked action.
		var parent: CombatEvent = by_id.get(event.parent_event_id)
		var ability_id := String(event.payload.get("ability_id",""))
		if ability_id.is_empty() and parent != null and parent.kind == CombatEvent.Kind.ATTACK:
			ability_id = String(parent.payload.get("ability_id",""))
		if ability_id.is_empty():
			var root: CombatEvent = _root_action(by_id,event)
			if root != null and root.source_id == event.source_id:
				ability_id = String(root.payload.get("ability_id",""))
		if not ability_id.is_empty():
			abi[ability_id] = int(abi.get(ability_id,0)) + dealt
			continue
		if parent != null and parent.kind == CombatEvent.Kind.ATTACK and bool(parent.payload.get("is_weapon_attack",false)):
			var bucket: Dictionary = weapon_oh if int(parent.payload.get("weapon_index",0)) > 0 else weapon_mh
			bucket["damage"] = int(bucket["damage"]) + dealt
		else:
			unattributed += dealt
	return {"mh":weapon_mh,"oh":weapon_oh,"abi_damage":abi,"dot_damage":dot,"dot_ticks":dot_ticks,"total_damage":total,"unattributed_damage":unattributed}

static func _root_action(by_id: Dictionary, event: CombatEvent) -> CombatEvent:
	var cursor: CombatEvent = event
	var visited: Dictionary = {}
	for _i in range(8):
		if cursor == null or cursor.parent_event_id <= 0 or visited.has(cursor.parent_event_id):
			break
		visited[cursor.parent_event_id] = true
		cursor = by_id.get(cursor.parent_event_id)
		if cursor != null and cursor.kind == CombatEvent.Kind.ACTION:
			return cursor
	return null

extends SceneTree

func _init() -> void:
	var state := CombatState.new()
	var source_a := CombatantState.new("SOURCE_A", "Source A", 50, 100, 0)
	var source_b := CombatantState.new("SOURCE_B", "Source B", 50, 100, 0)
	var target := CombatantState.new("TARGET", "Target", 50, 200, 0)
	state.add_combatant(source_a)
	state.add_combatant(source_b)
	state.add_combatant(target)
	var effects := {
		"EFF001": {"id":"EFF001","name":"Bleeding","kind":"dot","damage":2,"duration_rounds":3,"stacking":"stack","max_stacks":3},
		"BUFF001": {"id":"BUFF001","name":"Test Buff","kind":"crit_buff","crit_bonus":20.0,"duration_rounds":3,"stacking":"unique","max_stacks":1}
	}
	var engine := CombatEngine.new(state, {"effects":effects})

	# One Bleeding debuff may contain several stacks from different sources.
	for source_id in ["SOURCE_A", "SOURCE_B", "SOURCE_A", "SOURCE_B"]:
		engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT, source_id, "TARGET", {"effect_id":"EFF001","source_type":"item","source_instance_id":"ITEM_" + source_id}))
	var bleeding:Array = _effects(target, "EFF001")
	var bleed_sources:Array[String] = []
	for active in bleeding: bleed_sources.append(String(active.get("source_id", "")))
	var bleeding_ok := bleeding.size() == 3 and bleed_sources == ["SOURCE_A", "SOURCE_B", "SOURCE_A"]

	# UNIQUE buffs/debuffs never multiply: a new application replaces the old one.
	engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT, "SOURCE_A", "TARGET", {"effect_id":"BUFF001","source_type":"ability","source_instance_id":"ABI_A"}))
	engine.resolve_event(state.create_event(CombatEvent.Kind.EFFECT, "SOURCE_B", "TARGET", {"effect_id":"BUFF001","source_type":"ability","source_instance_id":"ABI_B"}))
	var buffs:Array = _effects(target, "BUFF001")
	var unique_ok := buffs.size() == 1 and String(buffs[0].get("source_id", "")) == "SOURCE_B" and String(buffs[0].get("source_instance_id", "")) == "ABI_B"

	var metadata_ok := true
	for active in bleeding:
		metadata_ok = metadata_ok and String(active.get("source_type", "")) == "item" and not String(active.get("source_instance_id", "")).is_empty() and not String(active.get("stack_id", "")).is_empty()

	var ok := bleeding_ok and unique_ok and metadata_ok
	print("EFF_STACKING bleeding=", bleeding.size(), " sources=", bleed_sources, " unique_buffs=", buffs.size(), " replacement_source=", String(buffs[0].get("source_id", "")) if not buffs.is_empty() else "none", " metadata=", metadata_ok)
	print("EFF_STACKING_TEST=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)

func _effects(target:CombatantState,effect_id:String)->Array:
	var result:Array = []
	for active in target.active_effects:
		if String(active.get("effect_id", "")) == effect_id: result.append(active)
	return result

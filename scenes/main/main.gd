extends Control

@onready var core_check: Label = $Center/VBox/CoreCheck


func _ready() -> void:
	_run_core_self_check()
	$Center/VBox/DebugMapViewer.pressed.connect(_open_debug_map_viewer)
	$Center/VBox/DebugCombatViewer.pressed.connect(_open_debug_combat_viewer)


func _run_core_self_check() -> void:
	var checks := [
		CombatMath.roll_success(35.0, 35),
		not CombatMath.roll_success(35.0, 36),
		is_equal_approx(CombatMath.effective_dodge(25.0, 10.0), 15.0),
		is_equal_approx(CombatMath.effective_crit(20.0, 5.0), 15.0),
		is_equal_approx(CombatMath.effective_armour(100.0, 20.0, 0.25), 60.0),
		CombatMath.final_damage_floor(12.99) == 12,
		CombatMath.final_damage_floor(-4.0) == 0,
		_run_event_model_check(),
	]

	if checks.all(func(value: bool) -> bool: return value):
		core_check.text = "Core self-check: PASS"
	else:
		core_check.text = "Core self-check: FAIL"


func _run_event_model_check() -> bool:
	var combat_state := CombatState.new()
	var attacker := CombatantState.new("hero", "Hero", 1, 100, 50)
	var defender := CombatantState.new("enemy", "Enemy", 1, 30, 0)
	combat_state.add_combatant(attacker)
	combat_state.add_combatant(defender)
	combat_state.begin_round()

	var damage_event := combat_state.create_event(
		CombatEvent.Kind.DAMAGE,
		attacker.combatant_id,
		defender.combatant_id,
		{"amount": 12.99, "damage_type": "slashing"}
	)
	combat_state.queue_event(damage_event)

	var engine := CombatEngine.new(combat_state)
	engine.resolve_pending_events()

	return (
		combat_state.round_number == 1
		and defender.hp == 18
		and combat_state.event_log.size() == 1
		and damage_event.result.get("final_damage") == 12
		and damage_event.result.get("connected") == true
	)


func _open_debug_map_viewer() -> void:
	get_tree().change_scene_to_file("res://scenes/debug/debug_map_viewer.tscn")


func _open_debug_combat_viewer() -> void:
	get_tree().change_scene_to_file("res://scenes/debug/debug_combat_viewer.tscn")

extends Control

@onready var core_check: Label = $Center/VBox/CoreCheck


func _ready() -> void:
	_run_core_self_check()


func _run_core_self_check() -> void:
	var checks := [
		CombatMath.roll_success(35.0, 35),
		not CombatMath.roll_success(35.0, 36),
		is_equal_approx(CombatMath.effective_dodge(25.0, 10.0), 15.0),
		is_equal_approx(CombatMath.effective_crit(20.0, 5.0), 15.0),
		is_equal_approx(CombatMath.effective_armour(100.0, 20.0, 0.25), 60.0),
		CombatMath.final_damage_floor(12.99) == 12,
		CombatMath.final_damage_floor(-4.0) == 0,
	]

	if checks.all(func(value: bool) -> bool: return value):
		core_check.text = "Core self-check: PASS"
	else:
		core_check.text = "Core self-check: FAIL"

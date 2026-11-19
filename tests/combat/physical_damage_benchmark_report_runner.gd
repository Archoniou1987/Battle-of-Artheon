extends SceneTree

## Presentation contract: sample numbers are fixtures, NOT measured balance.
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var sample := PhysicalDamageBenchmarkReport.format_archetype(
		"TEST_ARCHETYPE",1000,
		{"damage":780.0,"attempts":10},
		{
			"ABI301":{"damage":315.0,"casts":3},
			"ABI302":{"damage":100.0,"casts":2},
			"ABI303":{"no_damage":true,"casts":4}
		},
		{
			"ABI301":{"max_targets":1},
			"ABI302":{"max_targets":3},
			"ABI303":{"max_targets":1}
		}
	)
	for text_fragment in ["Обычные атаки (с критами) — 78","ABI301 — 105","ABI302 (×3) — 50","ABI303 — без урона"]:
		if not sample.contains(text_fragment):
			errors.append("missing: " + text_fragment)
	if not is_equal_approx(PhysicalDamageBenchmarkReport.mean_damage(120.0,3),40.0):
		errors.append("average_per_cast")
	if not is_equal_approx(PhysicalDamageBenchmarkReport.mean_damage(0.0,0),0.0):
		errors.append("safe_empty")
	print("PHYSICAL_DAMAGE_BENCHMARK_REPORT=", "PASS" if errors.is_empty() else "FAIL", " errors=",errors)
	quit(0 if errors.is_empty() else 1)

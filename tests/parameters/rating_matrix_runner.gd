extends SceneTree

func _initialize() -> void:
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 1), 20.0))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 100), 2.5))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 1), 50.0))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 100), 6.25))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 50), 20.0 - 17.5 * 49.0 / 99.0))
	print("RatingMatrix v1: PASS")
	quit(0)

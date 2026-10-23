extends SceneTree

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RatingMatrix.CONFIG_PATH))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 1), 10.0))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 100), 1.0))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 1), 25.0))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 100), 2.5))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 50), 10.0 - 9.0 * 49.0 / 99.0))
	assert(is_equal_approx(RatingMatrix.to_percent(-100.0, 1), -10.0)) # No invented universal cap.
	assert(RatingMatrix.to_percent(0, 100) == 0)
	var old_print := Engine.print_error_messages
	Engine.print_error_messages = false
	for level in [0,101,1.5,NAN,INF,"1"]:
		assert(is_nan(RatingMatrix.evaluate(100, level, config)))
	for rating in [NAN,INF,"bad",null]:
		assert(is_nan(RatingMatrix.evaluate(rating, 1, config)))
	for key in ["version","reference_rating","minimum_level","maximum_level","percent_at_level_1","percent_at_level_100","interpolation"]:
		var missing := config.duplicate(true)
		missing.erase(key)
		assert(is_nan(RatingMatrix.evaluate(100, 1, missing)))
	for bad_config in [{}, [], null]:
		assert(is_nan(RatingMatrix.evaluate(100, 1, bad_config)))
	for key in ["reference_rating","minimum_level","maximum_level","percent_at_level_1","percent_at_level_100"]:
		for bad_value in [NAN,INF,-1,"bad",null]:
			var bad := config.duplicate(true)
			bad[key] = bad_value
			assert(is_nan(RatingMatrix.evaluate(100, 1, bad)))
	assert(is_nan(RatingMatrix.to_percent(100, 1, "user://missing_rating_matrix.json")))
	Engine.print_error_messages = old_print
	print("RatingMatrix v1: PASS")
	quit(0)

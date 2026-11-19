extends SceneTree

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RatingMatrix.CONFIG_PATH))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 1), 20.0))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 100), 4.0))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 1), 50.0))
	assert(is_equal_approx(RatingMatrix.to_percent(250.0, 100), 10.0))
	assert(is_equal_approx(RatingMatrix.to_percent(100.0, 50), 20.0 - 16.0 * 49.0 / 99.0))
	assert(is_equal_approx(RatingMatrix.to_percent(-100.0, 1), -20.0)) # No invented universal cap.
	assert(RatingMatrix.to_percent(0, 100) == 0)
	# INT (PAR004) contributes no crit; INT hit/SP and intuition crit remain.
	# This is the single primary-stat rule, not a Combat Engine special case.
	var primary_base := {"PAR001":0,"PAR002":0,"PAR003":0,"PAR004":0,"PAR005":0,"PAR006":0}
	var from_zero := PrimaryStatEffects.calculate(primary_base)
	var from_int := primary_base.duplicate()
	from_int["PAR004"] = 50
	var int_effect := PrimaryStatEffects.calculate(from_int)
	assert(is_equal_approx(float(int_effect.get("crit_chance_rating",0.0)),float(from_zero.get("crit_chance_rating",0.0))))
	assert(is_equal_approx(float(int_effect.get("hit_chance_rating",0.0)),250.0))
	assert(is_equal_approx(float(int_effect.get("magic_damage_rating",0.0)),250.0))
	var from_intuition := primary_base.duplicate()
	from_intuition["PAR003"] = 50
	assert(is_equal_approx(float(PrimaryStatEffects.calculate(from_intuition).get("crit_chance_rating",0.0)),250.0))
	# Editing just the config values changes the calculation without code changes.
	var adjusted: Dictionary = config.duplicate(true)
	adjusted["percent_at_level_1"] = 30
	adjusted["percent_at_level_100"] = 8
	assert(is_equal_approx(RatingMatrix.evaluate(100.0,1,adjusted),30.0))
	assert(is_equal_approx(RatingMatrix.evaluate(100.0,100,adjusted),8.0))
	adjusted["reference_rating"] = 200
	assert(is_equal_approx(RatingMatrix.evaluate(100.0,1,adjusted),15.0))
	# Drift gate across five levels and varied ratings.
	for level in [1,25,50,75,100]:
		for rating in [0.0,1.0,100.0,250.0,1500.0]:
			var actual := RatingMatrix.to_percent(rating,level)
			assert(is_equal_approx(actual,CombatRatingCurves.rating_to_pct(rating,level)))
			assert(is_equal_approx(actual,ItemTemplateGeneratorV12.rating_to_pct(rating,level)))
	var old_print := Engine.print_error_messages
	Engine.print_error_messages = false
	# Legacy configuration cannot silently pass v1.2 validation.
	var obsolete: Dictionary = config.duplicate(true)
	obsolete["version"] = 1
	assert(is_nan(RatingMatrix.evaluate(100,1,obsolete)))
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
	print("RatingMatrix v1.2: PASS")
	quit(0)

extends SceneTree

func _initialize() -> void:
	var character := CharacterState.new("test-hero", "Hero")
	assert(character.level == 1)
	assert(character.award_xp(900) == 1)
	assert(character.level == 2)
	assert(character.progression.unspent_stat_points == 1)
	assert(character.allocate_stat("END"))
	var saved := character.progression_snapshot()
	var restored := CharacterState.new("restored-hero", "Hero")
	assert(restored.restore_progression(saved))
	assert(restored.level == 2)
	assert(restored.progression.base_stats["END"] == 4)
	print("Character state progression smoke: PASS")
	quit()

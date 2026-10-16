extends SceneTree

## End-to-end check of live Arena HP/mana -> CharacterState -> save file ->
## Inventory/Character UI -> reopened Arena -> restarted village.
var failures: Array[String] = []
const PROGRESSION_SAVE := "user://character_progression_v1.json"
const INVENTORY_SAVE := "user://character_inventory_v1.json"

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)

func _run() -> void:
	_remove_save(PROGRESSION_SAVE)
	_remove_save(INVENTORY_SAVE)
	var packed := load("res://scenes/main/main.tscn") as PackedScene
	if packed == null:
		check(false, "main scene missing")
		_finish()
		return
	var village := packed.instantiate()
	root.add_child(village)
	await process_frame
	var hero := village.get("player_character") as CharacterState
	var repository := village.get("item_repository") as ItemRepository
	if hero == null or repository == null:
		check(false, "village character/repository missing")
		_finish()
		return
	village.call("_open_panel", "Арена")
	await process_frame
	var arena := village.get_node_or_null("ArenaScreen") as ArenaScreen
	if arena == null or arena.combat_session == null:
		check(false, "Arena session did not start")
		_finish()
		return
	var player := arena.combat_session.fighter(true)
	var opponent := arena.combat_session.fighter(false)
	var expected_hp := maxi(1, player.max_hp - 12)
	var expected_mana := maxi(0, player.max_mana - 9)
	player.hp = expected_hp
	player.mana = expected_mana
	player.tempo = -1000.0
	opponent.tempo = -1000.0
	var attacks: Array[String] = ["chest"]
	var blocks: Array[String] = ["chest"]
	arena._play_combat_round(attacks, blocks)
	check(arena.combat_session.state.round_number == 1, "Arena completed the resource round")
	check(hero.current_hp == expected_hp, "Arena round updates persistent current HP")
	check(hero.current_mana == expected_mana, "Arena round updates persistent current mana")
	check((arena.hp_overlays["player"] as Label).text == "%d / %d" % [expected_hp, player.max_hp], "Arena HP overlay shows current/max")
	check((arena.mana_labels["player"] as Label).text == "%d / %d" % [expected_mana, player.max_mana], "Arena mana overlay shows current/max")
	check(FileAccess.file_exists(PROGRESSION_SAVE), "Arena resource changes saved immediately")
	if FileAccess.file_exists(PROGRESSION_SAVE):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESSION_SAVE))
		check(saved is Dictionary and int(saved.get("resources", {}).get("hp", -1)) == expected_hp and int(saved.get("resources", {}).get("mana", -1)) == expected_mana, "saved JSON has current Arena HP/mana")
	village.call("_open_panel", "Инвентарь")
	await process_frame
	var inventory := village.get_node_or_null("InventoryScreen") as InventoryScreen
	if inventory != null:
		check((inventory.hp_label as Label).text == "HP %d/%d" % [expected_hp, player.max_hp], "Inventory displays live current/max HP")
		check((inventory.stat_rows["Мана"] as Label).text == "%d / %d" % [expected_mana, player.max_mana], "Inventory displays live current/max mana")
	else:
		check(false, "Inventory screen missing")
	village.call("_open_panel", "Персонаж")
	await process_frame
	var character_screen := village.get_node_or_null("CharacterScreen") as CharacterScreen
	if character_screen != null:
		check(character_screen.resource_label.text.contains("HP %d/%d" % [expected_hp, player.max_hp]), "Character screen shows live HP")
		check(character_screen.resource_label.text.contains("Мана %d/%d" % [expected_mana, player.max_mana]), "Character screen shows live mana")
	else:
		check(false, "Character screen missing")
	village.call("_open_panel", "Арена")
	await process_frame
	var reopened := village.get_node_or_null("ArenaScreen") as ArenaScreen
	if reopened == null or reopened.combat_session == null:
		check(false, "second Arena session missing")
	else:
		check(reopened.combat_session.fighter(true).hp == expected_hp, "reopening Arena does not restore HP")
		check(reopened.combat_session.fighter(true).mana == expected_mana, "reopening Arena does not restore mana")
	village.queue_free()
	await process_frame
	var restarted := packed.instantiate()
	root.add_child(restarted)
	await process_frame
	var loaded := restarted.get("player_character") as CharacterState
	if loaded == null:
		check(false, "restarted character missing")
	else:
		check(loaded.current_hp == expected_hp, "HP persisted across scene restart")
		check(loaded.current_mana == expected_mana, "mana persisted across scene restart")
		var foreign := CombatantState.new("foreign", "Foreign", 1, 1, 1)
		check(not loaded.commit_combat_resources(foreign, restarted.get("item_repository") as ItemRepository), "cannot commit another fighter's resources")
		check(loaded.current_hp == expected_hp and loaded.current_mana == expected_mana, "invalid combat write-back does not mutate resources")
		loaded.current_hp = 0
		loaded.current_mana = 0
		restarted.call("_open_panel", "Арена")
		await process_frame
		var training := restarted.get_node_or_null("ArenaScreen") as ArenaScreen
		if training == null:
			check(false, "restarted Arena missing")
		else:
			check(training.round_button.disabled, "Arena does not enable attacks at zero HP")
			check(String(training.combat_session.play_round(attacks, blocks).get("reason", "")) == "player_has_no_hp", "Arena rejects zero-HP combat turn")
			training._refill_training_resources()
			var max_resources := loaded.resource_snapshot(restarted.get("item_repository") as ItemRepository)
			check(int(max_resources["hp"]) == int(max_resources["max_hp"]), "explicit training refill restores HP")
			check(int(max_resources["mana"]) == int(max_resources["max_mana"]), "explicit training refill restores mana")
			check(training.combat_session.fighter(true).hp == int(max_resources["max_hp"]), "training refill restarts a fresh combat snapshot")
	restarted.queue_free()
	await process_frame
	_remove_save(PROGRESSION_SAVE)
	_remove_save(INVENTORY_SAVE)
	_finish()

func _remove_save(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _finish() -> void:
	for failure in failures:
		push_error("ARENA_RESOURCE_PERSISTENCE: " + failure)
	print("ARENA_RESOURCE_PERSISTENCE_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

extends SceneTree

const SCENE_PATH := "res://scenes/main/main.tscn"
const ART_PATH := "res://assets/locations/starting_village.jpg"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_error("Starting village scene failed to load")
		quit(1)
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var area := instance.get_node_or_null("VBoxContainer")
	if area == null:
		# Main scene creates its UI dynamically; verify through recursive search.
		area = _find_named(instance, "Кузнец")
	var names := ["Кузнец", "Рынок", "Главное здание", "Тренировочное поле"]
	for name in names:
		var control := _find_named(instance, name)
		if control == null or not (control is Button):
			push_error("Missing village interaction: " + name)
			quit(1)
			return
	if not ResourceLoader.exists(ART_PATH):
		print("Village scene passed; approved artwork is not yet committed: " + ART_PATH)
	else:
		print("Village scene and artwork passed")
	quit(0)


func _find_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for child in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null

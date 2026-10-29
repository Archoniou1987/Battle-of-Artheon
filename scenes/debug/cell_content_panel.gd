class_name CellContentPanel
extends PanelContainer

## Compact view for the player's CURRENT hex. It owns no game state and
## does not perform pickup, combat or quest mutations.
signal entry_selected(kind: String, instance_id: String, action: String)
signal pickup_requested(instance_id: String)
signal pickup_cancel_requested()

var tabs: TabContainer
var entries_grid: GridContainer
var cell_label: Label
var details: Label
var events_label: Label
var pickup_button: Button
var cancel_button: Button
var pickup_status: Label
var pickup_progress: ProgressBar
var _selected_entry: Dictionary = {}
var _last_projection: Dictionary = {}

func _init() -> void:
	name = "CellContentPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	add_child(root)
	tabs = TabContainer.new()
	tabs.name = "WorldTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var content_tab := VBoxContainer.new()
	content_tab.name = "На клетке"
	content_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(content_tab)
	cell_label = Label.new()
	cell_label.text = "На клетке"
	content_tab.add_child(cell_label)
	var scroll := ScrollContainer.new()
	scroll.name = "CellIconsScroll"
	scroll.custom_minimum_size = Vector2(0,84)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_tab.add_child(scroll)
	entries_grid = GridContainer.new()
	entries_grid.name = "CellIcons"
	entries_grid.columns = 5
	entries_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_grid.add_theme_constant_override("h_separation",4)
	entries_grid.add_theme_constant_override("v_separation",4)
	scroll.add_child(entries_grid)
	details = Label.new()
	details.name = "InteractionDetails"
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.text = "Выберите объект"
	content_tab.add_child(details)
	var pickup_row := HBoxContainer.new()
	content_tab.add_child(pickup_row)
	pickup_button = Button.new()
	pickup_button.name = "PickUp"
	pickup_button.text = "Поднять (5 сек.)"
	pickup_button.visible = false
	pickup_button.pressed.connect(_request_pickup)
	pickup_row.add_child(pickup_button)
	cancel_button = Button.new()
	cancel_button.name = "CancelPickUp"
	cancel_button.text = "Отмена"
	cancel_button.visible = false
	cancel_button.pressed.connect(func()->void: pickup_cancel_requested.emit())
	pickup_row.add_child(cancel_button)
	pickup_status = Label.new()
	pickup_status.name = "PickupStatus"
	pickup_status.visible = false
	content_tab.add_child(pickup_status)
	pickup_progress = ProgressBar.new()
	pickup_progress.name = "PickupProgress"
	pickup_progress.min_value = 0.0
	pickup_progress.max_value = 5.0
	pickup_progress.show_percentage = false
	pickup_progress.visible = false
	content_tab.add_child(pickup_progress)
	var events_tab := VBoxContainer.new()
	events_tab.name = "События"
	tabs.add_child(events_tab)
	events_label = Label.new()
	events_label.text = "События мира будут доступны здесь."
	events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	events_tab.add_child(events_label)

func set_projection(projection: Dictionary) -> void:
	_last_projection = projection.duplicate(true)
	_selected_entry.clear()
	pickup_button.visible = false
	for node in entries_grid.get_children():
		entries_grid.remove_child(node)
		node.queue_free()
	if not bool(projection.get("ok",false)):
		cell_label.text = "На клетке"
		details.text = "Нет данных о текущей клетке."
		return
	var cell: Vector2i = projection.get("cell",Vector2i.ZERO)
	cell_label.text = "На клетке  %d:%d" % [cell.x,cell.y]
	details.text = "Выберите объект" if int(projection.get("total",0)) > 0 else "Здесь пока ничего нет."
	for entry in projection.get("entries",[]):
		if not entry is Dictionary:
			continue
		var kind := String(entry.get("kind",""))
		var id := String(entry.get("id",""))
		var button := Button.new()
		button.custom_minimum_size = Vector2(52,52)
		button.text = _symbol(kind)
		button.tooltip_text = String(entry.get("name",id))
		button.name = "Cell_" + kind + "_" + id.validate_node_name()
		button.pressed.connect(_select.bind(entry.duplicate(true)))
		entries_grid.add_child(button)

func _symbol(kind: String) -> String:
	match kind:
		CellContentService.KIND_ITEM:
			return "◆"
		CellContentService.KIND_NPC:
			return "⚔"
		CellContentService.KIND_RESOURCE:
			return "✿"
		CellContentService.KIND_OBJECT:
			return "◇"
		_:
			return "•"

func _select(entry: Dictionary) -> void:
	var kind := String(entry.get("kind",""))
	var id := String(entry.get("id",""))
	_selected_entry = entry.duplicate(true)
	pickup_button.visible = kind == CellContentService.KIND_ITEM and Array(entry.get("actions",[])).has("pick_up")
	var display_name := String(entry.get("name",id))
	var actions: Array = entry.get("actions",[])
	var action_names: PackedStringArray = []
	for action in actions:
		action_names.append(String(action))
	details.text = display_name + "  ·  " + ", ".join(action_names)
	# Emit a selection request only. The world owner must revalidate.
	entry_selected.emit(kind,id,String(actions[0]) if not actions.is_empty() else "inspect")

func show_events(message: String) -> void:
	events_label.text = message

func _request_pickup() -> void:
	if String(_selected_entry.get("kind","")) != CellContentService.KIND_ITEM:
		return
	if not Array(_selected_entry.get("actions",[])).has("pick_up"):
		return
	pickup_requested.emit(String(_selected_entry.get("id","")))

func show_pickup_progress(elapsed: float) -> void:
	pickup_button.visible = false
	cancel_button.visible = true
	pickup_progress.visible = true
	pickup_status.visible = true
	pickup_progress.value = clampf(elapsed,0.0,5.0)
	pickup_status.text = "Подбор: %.1f / 5 сек." % clampf(elapsed,0.0,5.0)

func finish_pickup_display(message: String) -> void:
	cancel_button.visible = false
	pickup_progress.visible = false
	pickup_status.visible = true
	pickup_status.text = message
	pickup_button.visible = String(_selected_entry.get("kind","")) == CellContentService.KIND_ITEM

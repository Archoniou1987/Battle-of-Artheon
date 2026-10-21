extends Control

const SCENE_TOWN := "res://scenes/main/main.tscn"
const SAVE := ExpeditionSaveService.DEFAULT_PATH
const MANIFEST := SoloCombatSessionManifest.PATH
const TOWN := SoloTownSaveService.DEFAULT_PATH
const PLAYER := "player"

var session: SoloLiveMapSession
var status_label: Label
var tile_container: GridContainer

func _ready() -> void:
	var id := SoloTownExpeditionBridge.expedition_id_for_player(PLAYER)
	var opened := SoloLiveMapSession.open(SAVE,MANIFEST,id,PLAYER)
	_build_view()
	if not bool(opened.get("ok",false)):
		_set_status("Экспедиция недоступна: "+String(opened.get("reason","unknown")))
		return
	session = opened["session"]
	_refresh()

func _build_view() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#172334")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation",12)
	scroll.add_child(root)
	var header := Label.new()
	header.text = "Экспедиция — первая игровая карта"
	header.add_theme_font_size_override("font_size",22)
	root.add_child(header)
	status_label = Label.new()
	root.add_child(status_label)
	var explanation := Label.new()
	explanation.text = "Перемещение: одна соседняя клетка. Каждый шаг сохраняется. NPC и бои появятся после подключения боевого интерфейса."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)
	tile_container = GridContainer.new()
	tile_container.columns = SoloLiveMapSession.WIDTH
	root.add_child(tile_container)
	var back := Button.new()
	back.text = "Завершить экспедицию и вернуться в деревню"
	back.pressed.connect(_return_town)
	root.add_child(back)

func _set_status(value: String) -> void:
	if status_label != null:
		status_label.text = value

func _refresh() -> void:
	if session == null:
		return
	_set_status("Позиция: %s   •   Персонаж: %s" % [str(session.expedition.player_position),session.character.display_name])
	for n in tile_container.get_children():
		tile_container.remove_child(n)
		n.queue_free()
	for y in range(SoloLiveMapSession.HEIGHT):
		for x in range(SoloLiveMapSession.WIDTH):
			var pos := Vector2i(x,y)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(37,35)
			if pos == session.expedition.player_position:
				btn.text = "◆"
			elif HexGrid.distance(session.expedition.player_position,pos) <= 3:
				btn.text = "·"
			else:
				btn.text = " "
			btn.disabled = HexGrid.distance(session.expedition.player_position,pos) != 1
			btn.pressed.connect(_move.bind(pos))
			tile_container.add_child(btn)

func _move(target: Vector2i) -> void:
	if session == null:
		return
	var moved := session.move_one_step(target)
	if not bool(moved.get("ok",false)):
		_set_status("Шаг отклонён: "+String(moved.get("reason","unknown")))
		return
	_refresh()

func _return_town() -> void:
	if session == null:
		return
	var result := session.return_to_town(TOWN)
	if not bool(result.get("ok",false)):
		_set_status("Возврат заблокирован: "+String(result.get("detail",result.get("reason","unknown"))))
		return
	get_tree().change_scene_to_file(SCENE_TOWN)

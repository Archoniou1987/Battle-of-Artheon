class_name ItemIcon
extends Button

## One square presentation for equipped items, bag items and future loot/shop cells.
const CELL_SIZE := 56.0
const EMPTY_ATLAS_PATH := "res://assets/ui/slots/BOA_EMPTY_EQUIPMENT_SLOTS_ATLAS_V2.png"
const EMPTY_SLOT_INDICES := {"head":0,"shoulders":1,"chest":2,"main_hand":3,"waist":4,"legs":5,"feet":6,"neck":7,"back":8,"wrists":9,"hands":10,"off_hand":11,"ring1":12,"ring2":12,"elixir":14,"abi":18,"bag":19}
static var _empty_atlas: Texture2D
static var _empty_cells: Dictionary = {}

static func empty_slot_texture(slot: String) -> Texture2D:
	if not EMPTY_SLOT_INDICES.has(slot):
		return null
	var index: int = int(EMPTY_SLOT_INDICES[slot])
	if _empty_cells.has(index):
		return _empty_cells[index] as Texture2D
	if _empty_atlas == null:
		if not ResourceLoader.exists(EMPTY_ATLAS_PATH):
			return null
		_empty_atlas = load(EMPTY_ATLAS_PATH) as Texture2D
	var result: Texture2D = _atlas_cell(_empty_atlas, index, 7, 3)
	_empty_cells[index] = result
	return result

const ATLAS_REGISTRY := "res://data/graphics/atlas_registry.json"
const ICON_REGISTRY := "res://data/graphics/icon_registry.json"
const ATLAS_PATH := "res://assets/items/items_atlas_01.png"
const ATLAS_COLUMNS := 8
const ATLAS_ROWS := 8
const RARITY_COLORS := {
	"grey": "#777f8a", "gray": "#777f8a", "common": "#aab0b8",
	"white": "#c5cbd2", "green": "#479c65", "uncommon": "#479c65",
	"blue": "#488acb", "rare": "#488acb", "purple": "#9867c5",
	"epic": "#d39a47", "orange": "#d39a47", "legendary": "#d95353", "red": "#d95353"
}

var instance_id := ""
var equipment_slot := ""
var is_equipped := false
var _icon_texture: TextureRect
var _fallback: Label
var _marker: Label
var _empty_background: TextureRect

func _ready() -> void:
	custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_text = true
	text = ""
	_empty_background = TextureRect.new()
	_empty_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_empty_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Keep the atlas cell square and inside the button: no stretching of metal borders.
	_empty_background.offset_left = 1
	_empty_background.offset_top = 1
	_empty_background.offset_right = -1
	_empty_background.offset_bottom = -1
	_empty_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_empty_background)
	_icon_texture = TextureRect.new()
	_icon_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_texture.offset_left = 5
	_icon_texture.offset_top = 5
	_icon_texture.offset_right = -5
	_icon_texture.offset_bottom = -5
	_icon_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon_texture)
	_fallback = Label.new()
	_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback.add_theme_font_size_override("font_size", 11)
	_fallback.add_theme_color_override("font_color", Color("#d9d1c3"))
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback)
	_marker = Label.new()
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_marker.add_theme_font_size_override("font_size", 14)
	_marker.add_theme_color_override("font_color", Color("#e5c57f"))
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)
	set_item({})

func set_item(item: Dictionary, slot_name: String = "", equipped: bool = false) -> void:
	equipment_slot = slot_name
	instance_id = String(item.get("instance_id", ""))
	is_equipped = equipped
	var rarity := String(item.get("rarity", "grey")).to_lower()
	var empty_key := _resolve_empty_slot(slot_name)
	var empty_texture: Texture2D = empty_slot_texture(empty_key) if item.is_empty() else null
	var border := Color(String(RARITY_COLORS.get(rarity, "#777f8a"))) if not item.is_empty() else Color("#66543d")
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#263346")
	style.border_color = border
	style.set_border_width_all(3)
	if not item.is_empty():
		style.shadow_color = Color(border.r, border.g, border.b, 0.78)
		style.shadow_size = 5
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	if empty_texture != null:
		style.bg_color = Color.TRANSPARENT
		style.set_border_width_all(0)
	add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#35465a") if empty_texture == null else Color.TRANSPARENT
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	var icon_path := String(item.get("icon_path", ""))
	var texture: Texture2D = null
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		texture = load(icon_path) as Texture2D
	elif item.has("icon_id"):
		texture = _texture_from_icon_id(String(item["icon_id"]))
	elif item.has("atlas_index") and ResourceLoader.exists(ATLAS_PATH):
		texture = _atlas_cell(load(ATLAS_PATH) as Texture2D, int(item["atlas_index"]), ATLAS_COLUMNS, ATLAS_ROWS)
	if _icon_texture == null:
		return
	_empty_background.texture = empty_texture
	_empty_background.visible = empty_texture != null
	_icon_texture.texture = texture
	_fallback.visible = texture == null and empty_texture == null
	_fallback.text = _short_label(String(item.get("name", ""))) if not item.is_empty() else _short_label(slot_name)
	_marker.text = ""
	tooltip_text = String(item.get("name", slot_name))

static func _resolve_empty_slot(value: String) -> String:
	if EMPTY_SLOT_INDICES.has(value):
		return value
	if value.begins_with("Эликсир"):
		return "elixir"
	if value.is_empty():
		return "bag"
	const LABEL_TO_SLOT := {"Голова":"head","Плечи":"shoulders","Грудь":"chest","Осн. рука":"main_hand","Пояс":"waist","Ноги":"legs","Ступни":"feet","Шея":"neck","Спина":"back","Наручи":"wrists","Перчатки":"hands","Вторая рука":"off_hand","Кольцо I":"ring1","Кольцо II":"ring2"}
	return String(LABEL_TO_SLOT.get(value, ""))

func _short_label(value: String) -> String:
	if value.is_empty():
		return "·"
	return value.substr(0, mini(4, value.length()))


# Registries are authoritative; atlas_index remains only as a temporary legacy fallback.
static func _texture_from_icon_id(icon_id: String) -> Texture2D:
	var icons := _read_registry(ICON_REGISTRY, "icons")
	var atlases := _read_registry(ATLAS_REGISTRY, "atlases")
	for icon in icons:
		if not icon is Dictionary or String(icon.get("icon_id", "")) != icon_id:
			continue
		for atlas in atlases:
			if not atlas is Dictionary:
				continue
			if String(atlas.get("atlas_id", "")) != String(icon.get("atlas_id", "")) or int(atlas.get("version", -1)) != int(icon.get("atlas_version", -1)):
				continue
			var path := String(atlas.get("path", ""))
			if not ResourceLoader.exists(path):
				return null
			return _atlas_cell(load(path) as Texture2D, int(icon.get("cell_index", -1)), int(atlas.get("columns", 0)), int(atlas.get("rows", 0)))
	return null


static func _read_registry(path: String, collection: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var values: Variant = parsed.get(collection, [])
		if values is Array:
			return values
	return []


static func _atlas_cell(atlas: Texture2D, index: int, columns: int, rows: int) -> Texture2D:
	if atlas == null or columns <= 0 or rows <= 0 or index < 0 or index >= columns * rows:
		return null
	var cell := Vector2i(atlas.get_width() / columns, atlas.get_height() / rows)
	if cell.x <= 0 or cell.y <= 0:
		return null
	var cropped := AtlasTexture.new()
	cropped.atlas = atlas
	cropped.region = Rect2(Vector2i(index % columns, index / columns) * cell, cell)
	return cropped

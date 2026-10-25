class_name ItemIcon
extends Button

## One square presentation for equipped items, bag items and future loot/shop cells.
const CELL_SIZE := 56.0
const SLOT_BACKGROUND_PATH := "res://assets/ui/slots/BOA_SLOT_BACKGROUND_V1.png"
const SLOT_FRAME_PATH := "res://assets/ui/slots/BOA_SLOT_FRAME_V1.png"
const SHOW_DECORATIVE_SLOT_FRAMES := false
const NEW_EMPTY_ATLAS_PATH := "res://assets/ui/slots/BOA_EMPTY_SLOT_ICONS_ATLAS_V3.png"
const NEW_EMPTY_SLOT_INDICES := {"head":0,"shoulders":1,"chest":2,"main_hand":3,"waist":4,"legs":5,"feet":6,"neck":7,"back":8,"wrists":9,"hands":10,"off_hand":11,"ring1":12,"ring2":12,"elixir":13,"bag":14}
const EMPTY_ATLAS_PATH := "res://assets/ui/slots/BOA_EMPTY_EQUIPMENT_SLOTS_ATLAS_V2.png"
const EMPTY_SPRITE_DIR := "res://assets/ui/slots/empty_slots/"
const EMPTY_SPRITE_FILES := ["empty_00_head.png", "empty_01_shoulders.png", "empty_02_chest.png", "empty_03_main_hand.png", "empty_04_waist.png", "empty_05_legs.png", "empty_06_feet.png", "empty_07_neck.png", "empty_08_back.png", "empty_09_wrists.png", "empty_10_hands.png", "empty_11_off_hand.png", "empty_12_ring1.png", "empty_13_ring2.png", "empty_14_elixir1.png", "empty_15_elixir2.png", "empty_16_elixir3.png", "empty_17_elixir4.png", "empty_18_abi.png", "empty_19_bag.png", "empty_20_unused.png"]
const EMPTY_SLOT_INDICES := {"head":0,"shoulders":1,"chest":2,"main_hand":3,"waist":4,"legs":5,"feet":6,"neck":7,"back":8,"wrists":9,"hands":10,"off_hand":11,"ring1":12,"ring2":12,"elixir":14,"abi":18,"bag":19}
static var _new_empty_atlas: Texture2D
static var _new_empty_cells: Dictionary = {}
static var _empty_atlas: Texture2D
static var _empty_cells: Dictionary = {}

static func empty_slot_texture(slot: String) -> Texture2D:
	if NEW_EMPTY_SLOT_INDICES.has(slot) and ResourceLoader.exists(NEW_EMPTY_ATLAS_PATH):
		if _new_empty_atlas == null:
			_new_empty_atlas = load(NEW_EMPTY_ATLAS_PATH) as Texture2D
		if _new_empty_atlas != null:
			var new_index: int = int(NEW_EMPTY_SLOT_INDICES[slot])
			if not _new_empty_cells.has(new_index):
				_new_empty_cells[new_index] = _atlas_cell(_new_empty_atlas, new_index, 5, 3)
			return _new_empty_cells[new_index] as Texture2D
	if not EMPTY_SLOT_INDICES.has(slot):
		return null
	var index: int = int(EMPTY_SLOT_INDICES[slot])
	if _empty_cells.has(index):
		return _empty_cells[index] as Texture2D
	# Prefer verified, individually cropped textures when installed.
	# Legacy atlas fallback keeps existing scenes functional during asset upload.
	if index >= 0 and index < EMPTY_SPRITE_FILES.size():
		var sprite_path: String = EMPTY_SPRITE_DIR + String(EMPTY_SPRITE_FILES[index])
		if ResourceLoader.exists(sprite_path):
			var sprite := load(sprite_path) as Texture2D
			if sprite != null:
				_empty_cells[index] = sprite
				return sprite
	if _empty_atlas == null:
		if not ResourceLoader.exists(EMPTY_ATLAS_PATH):
			return null
		_empty_atlas = load(EMPTY_ATLAS_PATH) as Texture2D
	var result: Texture2D = _atlas_cell(_empty_atlas, index, 7, 3)
	_empty_cells[index] = result
	return result

const ATLAS_REGISTRY := "res://data/graphics/atlas_registry.json"
const ICON_REGISTRY := "res://data/graphics/icon_registry.json"
const ATLAS_PATH := "res://assets/items/BOA_ITEMS_LEVEL_1-5_ATLAS_RGBA.png"
const RARITY_ATLAS_PATH := "res://assets/ui/slots/BOA_RARITY_BACKGROUNDS_3x2_768x512.png"
const INNER_MASK_PATH := "res://assets/ui/slots/BOA_ITEM_INNER_RARITY_CLIP_MASK_256.png"
const ICON_INSET := 0.055 # 5.5% from each edge; preserves already-cropped atlas art.
static var _rarity_atlas: Texture2D
static var _rarity_cells: Dictionary = {}
static var _clip_shader: Shader
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
## Enable only after the square base PNG has the empty slot and frame baked in.
var empty_art_in_background := false
## Preview layout with only neutral empty-slot frames (no ghost icons).
var show_empty_placeholder_icon := true
var _shown_item: Dictionary = {}
var _icon_texture: TextureRect
var _fallback: Label
var _marker: Label
var _empty_background: TextureRect
var _slot_background: TextureRect
var _slot_frame: TextureRect
var _rarity_background: TextureRect

func _ready() -> void:
	custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_text = true
	text = ""
	_slot_background = TextureRect.new()
	_slot_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slot_background.stretch_mode = TextureRect.STRETCH_SCALE
	_slot_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SLOT_BACKGROUND_PATH):
		_slot_background.texture = load(SLOT_BACKGROUND_PATH) as Texture2D
	add_child(_slot_background)
	_rarity_background = TextureRect.new()
	_rarity_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rarity_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rarity_background.stretch_mode = TextureRect.STRETCH_SCALE
	_rarity_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rarity_background)
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
	_icon_texture.offset_left = CELL_SIZE * ICON_INSET
	_icon_texture.offset_top = CELL_SIZE * ICON_INSET
	_icon_texture.offset_right = -CELL_SIZE * ICON_INSET
	_icon_texture.offset_bottom = -CELL_SIZE * ICON_INSET
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
	_slot_frame = TextureRect.new()
	_slot_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slot_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_slot_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(SLOT_FRAME_PATH):
		_slot_frame.texture = load(SLOT_FRAME_PATH) as Texture2D
	add_child(_slot_frame)
	_marker = Label.new()
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_marker.add_theme_font_size_override("font_size", 14)
	_marker.add_theme_color_override("font_color", Color("#e5c57f"))
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker)
	# Input/state lives above the item and empty-slot artwork.
	SquareSlotFeedback.attach(self, "equipment")
	set_item({})

func set_empty_art_in_background(enabled: bool) -> void:
	if empty_art_in_background == enabled:
		return
	empty_art_in_background = enabled
	if _icon_texture != null:
		set_item(_shown_item, equipment_slot, is_equipped)

func set_empty_placeholder_icon_visible(enabled: bool) -> void:
	if show_empty_placeholder_icon == enabled:
		return
	show_empty_placeholder_icon = enabled
	if _icon_texture != null:
		set_item(_shown_item, equipment_slot, is_equipped)

func set_item(item: Dictionary, slot_name: String = "", equipped: bool = false) -> void:
	_shown_item = item.duplicate(true)
	equipment_slot = slot_name
	instance_id = String(item.get("instance_id", ""))
	is_equipped = equipped
	var rarity := String(item.get("rarity", "grey")).to_lower()
	var empty_key := _resolve_empty_slot(slot_name)
	var empty_texture: Texture2D = empty_slot_texture(empty_key) if item.is_empty() and show_empty_placeholder_icon and not empty_art_in_background else null
	var border := Color(String(RARITY_COLORS.get(rarity, "#777f8a"))) if not item.is_empty() else Color("#66543d")
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT if not item.is_empty() else Color("#263346")
	style.border_color = border
	style.set_border_width_all(0)
	# The PNG rarity cell supplies the entire frame; no legacy colour outline.
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	# Rarity border is exclusively the equipped item's UI; the empty
	# background contains only an unchanging dark square and faint frame.
	if item.is_empty():
		style.bg_color = Color.TRANSPARENT if empty_texture != null or empty_art_in_background else Color("#263346")
		style.border_color = Color("#83B8D9", 0.65)
		style.set_border_width_all(0 if empty_art_in_background and show_empty_placeholder_icon else (2 if not show_empty_placeholder_icon else 1))
	add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#35465a") if empty_texture == null and not ResourceLoader.exists(SLOT_BACKGROUND_PATH) else Color.TRANSPARENT
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
	var use_new_slot_art := show_empty_placeholder_icon and ResourceLoader.exists(NEW_EMPTY_ATLAS_PATH) and ResourceLoader.exists(SLOT_BACKGROUND_PATH)
	_slot_background.visible = use_new_slot_art and item.is_empty() and not empty_art_in_background
	_rarity_background.texture = _rarity_texture(rarity) if not item.is_empty() else null
	_rarity_background.visible = _rarity_background.texture != null
	_slot_frame.visible = use_new_slot_art and SHOW_DECORATIVE_SLOT_FRAMES and item.is_empty() and not empty_art_in_background
	_empty_background.texture = empty_texture
	_empty_background.visible = empty_texture != null
	_icon_texture.texture = texture
	_apply_inner_clip(not item.is_empty() and texture != null and _rarity_background.visible)
	_fallback.visible = texture == null and empty_texture == null and not item.is_empty()
	_fallback.text = _short_label(String(item.get("name", ""))) if not item.is_empty() else _short_label(slot_name)
	_marker.text = ""
	var readable_slot := SquareUiGeometry.equipment_name(empty_key) if not empty_key.is_empty() and not ["elixir", "bag", "abi"].has(empty_key) else slot_name
	tooltip_text = (String(item.get("name", readable_slot)) if not item.is_empty() else (readable_slot + " — пусто" if not readable_slot.is_empty() else "Пустая ячейка"))

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
	var column := index % columns
	var row := index / columns
	var x0 := roundi(float(column) * float(atlas.get_width()) / float(columns))
	var x1 := roundi(float(column + 1) * float(atlas.get_width()) / float(columns))
	var y0 := roundi(float(row) * float(atlas.get_height()) / float(rows))
	var y1 := roundi(float(row + 1) * float(atlas.get_height()) / float(rows))
	var cell := Vector2i(x1 - x0, y1 - y0)
	if cell.x <= 0 or cell.y <= 0:
		return null
	var cropped := AtlasTexture.new()
	cropped.atlas = atlas
	cropped.region = Rect2(Vector2i(x0, y0), cell)
	cropped.filter_clip = true
	return cropped


static func _rarity_texture(rarity: String) -> Texture2D:
	if not ResourceLoader.exists(RARITY_ATLAS_PATH):
		return null
	if _rarity_atlas == null:
		_rarity_atlas = load(RARITY_ATLAS_PATH) as Texture2D
	var indices := {"grey": 0, "gray": 0, "common": 0, "white": 0, "green": 1, "uncommon": 1, "blue": 2, "rare": 2, "purple": 3, "epic": 3, "orange": 4, "legendary": 4, "red": 5}
	var index: int = int(indices.get(rarity, 0))
	if not _rarity_cells.has(index):
		_rarity_cells[index] = _atlas_cell(_rarity_atlas, index, 3, 2)
	return _rarity_cells[index] as Texture2D

func _apply_inner_clip(enabled: bool) -> void:
	if not enabled or not ResourceLoader.exists(INNER_MASK_PATH):
		_icon_texture.material = null
		return
	if _clip_shader == null:
		_clip_shader = Shader.new()
		_clip_shader.code = "shader_type canvas_item; uniform sampler2D clip_mask : filter_linear; void fragment() { vec4 item = texture(TEXTURE, UV); float mask_alpha = texture(clip_mask, UV).a; COLOR = item * vec4(1.0, 1.0, 1.0, mask_alpha); }"
	var material := ShaderMaterial.new()
	material.shader = _clip_shader
	material.set_shader_parameter("clip_mask", load(INNER_MASK_PATH) as Texture2D)
	_icon_texture.material = material

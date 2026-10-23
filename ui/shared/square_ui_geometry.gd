class_name SquareUiGeometry
extends RefCounted

## Fixed 1:1 panel geometry. The square's 480x480 local coordinates never
## rearrange for landscape/portrait; only the outer size changes.
const DESIGN_EDGE := 480.0
const EQUIPMENT_LABELS := {
	"head":"Шлем", "shoulders":"Наплечники", "chest":"Нагрудная броня",
	"main_hand":"Основное оружие", "waist":"Пояс", "legs":"Поножи",
	"feet":"Обувь", "neck":"Ожерелье", "back":"Плащ",
	"wrists":"Наручи", "hands":"Перчатки", "off_hand":"Левая рука",
	"ring1":"Кольцо 1", "ring2":"Кольцо 2"
}
const ABI_SOURCE_LABELS := [
	"Оружие MH — ABI 1", "Оружие MH — ABI 2", "Оружие MH — ABI 3",
	"Нагрудная броня — ABI", "Шлем — ABI"
]

static func fit(host: Control, content: Control, requested_edge: float, design_edge: float = DESIGN_EDGE) -> void:
	if host == null or content == null or design_edge <= 0.0:
		return
	var edge := floorf(maxf(1.0, requested_edge))
	host.custom_minimum_size = Vector2(edge, edge)
	host.size = Vector2(edge, edge)
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.position = Vector2.ZERO
	content.size = Vector2.ONE * design_edge
	content.scale = Vector2.ONE * (edge / design_edge)

static func equipment_name(slot: String) -> String:
	return String(EQUIPMENT_LABELS.get(slot, slot))

static func abi_source(index: int) -> String:
	return String(ABI_SOURCE_LABELS[index]) if index >= 0 and index < ABI_SOURCE_LABELS.size() else "ABI"

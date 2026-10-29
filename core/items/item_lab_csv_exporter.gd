class_name ItemLabCsvExporter
extends RefCounted

## One self-contained, UTF-8 Excel-compatible semicolon CSV:
## CONFIG -> effective PAR -> one ITEM row per rarity/instance.
## Stable named columns and JSON values make it easy to re-import/analyze.
const SCHEMA := "BOA_ITEM_LAB_CSV_V1"
const COLUMNS := [
	"row_type", "key", "value_json", "item_id", "form_id", "item_type", "slot",
	"level", "rarity", "damage_min", "damage_max", "requirements_json",
	"armor_json", "par_bonuses_json", "bonus_rolls_json", "requirement_rule",
	"requirement_sources_json", "par_details_json"
]

static func build(config: Dictionary, result: Dictionary, lab: ItemBalanceWorkbench) -> String:
	var lines: Array[String] = []
	lines.append(_csv_line(COLUMNS))
	_append_meta(lines, "format", SCHEMA)
	_append_meta(lines, "generator", "ItemBalanceWorkbench: independent BoA formulas")
	_append_meta(lines, "generator_version", 1)
	_append_meta(lines, "requirement_rule", ItemBalanceWorkbench.REQUIREMENT_RULE)
	_append_meta(lines, "selected_requirement_rule", ItemBalanceWorkbench.SELECTED_REQUIREMENT_RULE)
	_append_meta(lines, "requirement_slot_factors", ItemBalanceWorkbench.REQUIREMENT_SLOT_FACTOR)
	_append_meta(lines, "weapon_definitions", ItemBalanceWorkbench.WEAPONS)
	_append_meta(lines, "armor_pieces", ItemBalanceWorkbench.PIECES)
	_append_meta(lines, "armor_classes", ItemBalanceWorkbench.CLASSES)
	_append_meta(lines, "item_shape_factors", ItemBalanceWorkbench.SHAPE)
	_append_meta(lines, "rarity_unlock_levels", ItemBalanceWorkbench.RARITY_LEVEL)
	_append_meta(lines, "affix_primary_mapping", ItemBalanceWorkbench.AFFIX_PRIMARY)
	_append_meta(lines, "affix_formula", "MAX * 0.011 * pow(level / 25, PAR.growth) * PAR.value_scale * bonus_scale * (1 ± spread)")
	_append_meta(lines, "damage_formula", "(level + 2) * item_damage_factor * item_shape * damage_scale; min=88%, max=112%")
	_append_meta(lines, "requirements_formula", "(18 + 2*(level-1)) * requirement_pct / 100 * level_opening * slot_factor / count(required primary stats); selected archetype PAR take precedence")
	_append_meta(lines, "requested_count", int(result.get("requested", 0)))
	_append_meta(lines, "actual_count", (result.get("rows", []) as Array).size())
	_append_meta(lines, "available_unique", int(result.get("available_unique", 0)))
	var config_keys: Array = config.keys()
	config_keys.sort()
	for raw in config_keys:
		var key := String(raw)
		_append_row(lines, "CONFIG", key, config[key])
	var active: Dictionary = config.get("par_weights", {})
	var overrides: Dictionary = config.get("par_settings", {})
	var par_keys: Array = active.keys()
	par_keys.sort()
	for raw in par_keys:
		var par := String(raw)
		if not lab.registry.has(par):
			continue
		var effective: Dictionary = lab.parameter_settings(par, overrides)
		effective["name"] = lab.par_name(par)
		effective["weight"] = active[par]
		if lab.is_percentage(par):
			effective["pct_per_100_at_level_25"] = lab.percentage(par, 100.0, 25, overrides)
			effective["pct_per_100_at_level_30"] = lab.percentage(par, 100.0, 30, overrides)
		_append_row(lines, "PAR_EFFECTIVE", par, effective)
	for raw in result.get("rows", []):
		var row: Dictionary = raw
		for raw_variant in row.get("variants", []):
			var variant: Dictionary = raw_variant
			var damage: Array = variant.get("damage", [])
			var damage_min: Variant = damage[0] if damage.size() > 0 else ""
			var damage_max: Variant = damage[1] if damage.size() > 1 else ""
			var details: Array = []
			var par_data: Dictionary = variant.get("total_par", {})
			var stats: Array = par_data.keys()
			stats.sort()
			for stat in stats:
				var id := String(stat)
				var item: Dictionary = {"id":id,"name":lab.par_name(id),"rating":int(par_data[stat])}
				if lab.is_percentage(id):
					item["percent"] = lab.percentage(id, float(par_data[stat]), int(row.get("level", 1)), overrides)
				details.append(item)
			var fields: Array = [
				"ITEM", "", "", row.get("id", ""), row.get("source_template", ""),
				row.get("item_type", ""), row.get("slot", ""), row.get("level", ""),
				variant.get("quality", ""), damage_min, damage_max,
				JSON.stringify(variant.get("requirements", {})),
				JSON.stringify(variant.get("armour", {})),
				JSON.stringify(par_data),
				JSON.stringify(variant.get("rolls", [])),
				variant.get("requirement_rule", ""),
				JSON.stringify(variant.get("requirement_sources", {})),
				JSON.stringify(details)
			]
			lines.append(_csv_line(fields))
	# BOM is important for Cyrillic text when opened in spreadsheet applications.
	return "\uFEFF" + "\n".join(PackedStringArray(lines)) + "\n"

static func _append_meta(lines: Array[String], key: String, value: Variant) -> void:
	_append_row(lines, "META", key, value)

static func _append_row(lines: Array[String], group: String, key: String, value: Variant) -> void:
	var cells: Array = [group, key, JSON.stringify(value)]
	while cells.size() < COLUMNS.size():
		cells.append("")
	lines.append(_csv_line(cells))

static func _csv_line(fields: Array) -> String:
	var escaped: Array[String] = []
	for value in fields:
		var cell := str(value).replace("\"", "\"\"")
		escaped.append("\"" + cell + "\"")
	return ";".join(PackedStringArray(escaped))

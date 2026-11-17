class_name PhysicalDamageBenchmarkReport
extends RefCounted

## Presentation only. Input figures are actual post-mitigation sums and cast/
## attack counts gathered from the canonical Combat Engine event history.
## One-target damage is NEVER multiplied by an AoE target count.
static func mean_damage(total_damage: float, attempts: int) -> float:
	return total_damage / float(attempts) if attempts > 0 else 0.0

static func format_archetype(archetype: String, battles: int, attacks: Dictionary, abilities: Dictionary, definitions: Dictionary) -> String:
	var lines: Array[String] = [
		"%s · уровень 40" % archetype,
		"%d боёв · 1 цель · броня ~20%%" % battles
	]
	var basic_total := float(attacks.get("damage",0))
	var basic_count := int(attacks.get("attempts",0))
	lines.append("Обычные атаки (с критами) — %s" % _format_average(basic_total,basic_count))
	var ids: Array[String] = []
	for raw_id in abilities.keys():
		ids.append(String(raw_id))
	ids.sort()
	for id in ids:
		var tally: Dictionary = Dictionary(abilities[id])
		var def: Dictionary = Dictionary(definitions.get(id,{}))
		var target_count := maxi(1,int(def.get("max_targets",1)))
		var aoe_note := " (×%d)" % target_count if target_count > 1 else ""
		var ability_label := "%s%s" % [id,aoe_note]
		if bool(tally.get("no_damage",false)):
			lines.append("%s — без урона" % ability_label)
		else:
			lines.append("%s — %s" % [ability_label,_format_average(float(tally.get("damage",0)),int(tally.get("casts",0)))])
	return "\n".join(lines)

static func _format_average(damage: float, attempts: int) -> String:
	if attempts < 1:
		return "нет применений"
	return str(roundi(mean_damage(damage,attempts)))

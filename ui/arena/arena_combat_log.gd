class_name ArenaCombatLog
extends RefCounted

## View-only projection of resolved CombatEvent ancestry. The journal must never
## recalculate damage/healing or modify state. Ability ATTACK -> DAMAGE children
## belong to ONE ABI and must not masquerade as extra physical actions.
static func lines_for_round(events: Array[CombatEvent], round_number: int, player_id: String, ability_definitions: Dictionary = {}) -> Array[String]:
	var by_id: Dictionary = {}
	var weapon_damage: Dictionary = {}
	var summaries: Dictionary = {}
	var abi_hit_details: Dictionary = {}
	var result: Array[String] = []
	var effects_catalog: Dictionary = EffectCatalog.load_json()
	for event in events:
		if int(event.payload.get("round", -1)) != round_number:
			continue
		by_id[event.event_id] = event
	for event in events:
		if int(event.payload.get("round", -1)) != round_number:
			continue
		var root_id: int = _ability_root_id(event, by_id)
		if root_id >= 0 and event.event_id != root_id:
			var summary: Dictionary = summaries.get(root_id, {
				"damage": 0, "burst_damage": 0, "burst_ticks": 0, "healing": 0, "effects": [], "removed": [],
				"missed_effects": [], "failed_hits": []
			})
			if event.kind == CombatEvent.Kind.DAMAGE:
				var resolved_damage: int = int(event.result.get("hp_removed", 0))
				summary["damage"] = int(summary["damage"]) + resolved_damage
				if abi_hit_details.has(event.parent_event_id):
					var linked_hit: Dictionary = abi_hit_details[event.parent_event_id]
					linked_hit["damage"] = int(linked_hit.get("damage", 0)) + resolved_damage
					abi_hit_details[event.parent_event_id] = linked_hit
				if bool(event.payload.get("sword_burst_tick", false)):
					summary["burst_damage"] = int(summary["burst_damage"]) + resolved_damage
					summary["burst_ticks"] = int(summary["burst_ticks"]) + 1
			elif event.kind == CombatEvent.Kind.ATTACK:
				var status: String = String(event.result.get("outcome", ""))
				var hit: Dictionary = {
					"event_id": event.event_id,
					"index": int(event.payload.get("dagger_strike_index", -1)),
					"zone": String(event.payload.get("zone", "chest")),
					"critical": bool(event.result.get("critical", false)),
					"outcome": status,
					"damage": 0
				}
				abi_hit_details[event.event_id] = hit
				var hit_ids: Array = summary.get("hit_ids", [])
				hit_ids.append(event.event_id)
				summary["hit_ids"] = hit_ids
				if status != "connected" and not status.is_empty():
					var failures: Array = summary["failed_hits"]
					failures.append(_attack_outcome(status))
			elif event.kind == CombatEvent.Kind.EFFECT:
				if event.payload.has("inline_heal"):
					summary["healing"] = int(summary["healing"]) + int(event.result.get("healed", 0))
				elif event.payload.has("dispel_polarity"):
					var removed: Array = summary["removed"]
					for raw_id in Array(event.result.get("removed_effect_ids", [])):
						removed.append(String(raw_id))
				elif bool(event.result.get("resolved", false)):
					if event.result.has("healed"):
						summary["healing"] = int(summary["healing"]) + int(event.result.get("healed", 0))
					elif not String(event.payload.get("effect_id", "")).is_empty():
						var applied: Array = summary["effects"]
						applied.append(String(event.payload.get("effect_id", "")))
				elif not String(event.payload.get("effect_id", "")).is_empty():
					var missed: Array = summary["missed_effects"]
					missed.append(String(event.payload.get("effect_id", "")))
			summaries[root_id] = summary
		elif root_id < 0 and event.kind == CombatEvent.Kind.DAMAGE and event.parent_event_id >= 0:
			weapon_damage[event.parent_event_id] = int(weapon_damage.get(event.parent_event_id, 0)) + int(event.result.get("hp_removed", 0))
	for event in events:
		if int(event.payload.get("round", -1)) != round_number:
			continue
		var root_id: int = _ability_root_id(event, by_id)
		if root_id == event.event_id and event.kind == CombatEvent.Kind.ACTION:
			var name_id: String = String(event.payload.get("ability_id", ""))
			# ABI301 enhances the ordinary MH strike: render one named attack line instead of a second technical ability line.
			if name_id == "ABI301" and String(event.result.get("outcome", "")) == "linked_to_existing_mh":
				continue
			var definition: Dictionary = AbilityCatalog.definition(ability_definitions, name_id)
			var ability_name: String = String(definition.get("name", name_id))
			var prefix: String = "%s — ABI «%s»" % [_actor(event.source_id, player_id), ability_name]
			var values: Dictionary = summaries.get(event.event_id, {})
			var parts: PackedStringArray = []
			if int(values.get("burst_ticks", 0)) > 0:
				var total_damage: int = int(values.get("damage", 0))
				var bleed_damage: int = int(values.get("burst_damage", 0))
				parts.append("%d урона (удар %d + %d ускоренных тика кровотечения: %d)" % [total_damage, total_damage - bleed_damage, int(values["burst_ticks"]), bleed_damage])
			elif int(values.get("damage", 0)) > 0:
				parts.append("%d урона" % int(values.get("damage", 0)))
			var hit_ids: Array = values.get("hit_ids", [])
			var critical_count := 0
			for raw_hit_id in hit_ids:
				var hit: Dictionary = abi_hit_details.get(int(raw_hit_id), {})
				if bool(hit.get("critical", false)):
					critical_count += 1
			if name_id != "ABI406" and critical_count > 0:
				parts.append("крит: %d/%d" % [critical_count, hit_ids.size()])
			if int(values.get("healing", 0)) > 0:
				parts.append("+%d HP" % int(values.get("healing", 0)))
			for effect_id in Array(values.get("effects", [])):
				parts.append("наложен %s" % _effect_name(String(effect_id), effects_catalog))
			for effect_id in Array(values.get("removed", [])):
				parts.append("снят %s" % _effect_name(String(effect_id), effects_catalog))
			for effect_id in Array(values.get("missed_effects", [])):
				parts.append("%s не наложен" % _effect_name(String(effect_id), effects_catalog))
			if name_id != "ABI406":
				for missed_hit in Array(values.get("failed_hits", [])):
					parts.append(String(missed_hit))
			if parts.is_empty():
				var reason: String = String(event.result.get("outcome", ""))
				parts.append(_ability_outcome(reason))
			result.append(prefix + ": " + "; ".join(parts))
			if name_id == "ABI406":
				# Display real resolved events, without rolling or applying damage again.
				for raw_hit_id in hit_ids:
					var hit: Dictionary = abi_hit_details.get(int(raw_hit_id), {})
					var hit_index: int = int(hit.get("index", -1))
					var strike_number: int = hit_index + 1 if hit_index >= 0 else hit_ids.find(raw_hit_id) + 1
					var hand := "MH" if hit_index < 0 or hit_index % 2 == 0 else "OH"
					var status: String = String(hit.get("outcome", ""))
					var strike_result := "%d урона%s" % [int(hit.get("damage", 0)), " (крит)" if bool(hit.get("critical", false)) else ""] if status == "connected" else _attack_outcome(status)
					result.append("  Удар %d (%s, %s): %s" % [strike_number, hand, _zone_name(String(hit.get("zone", "chest"))), strike_result])
		elif event.kind == CombatEvent.Kind.ATTACK and root_id < 0:
			var outcome: String = String(event.result.get("outcome", ""))
			var from_name: String = _actor(event.source_id, player_id)
			var target_name: String = _target(event.target_id, player_id)
			var zone_name: String = _zone_name(String(event.payload.get("zone", "chest")))
			if outcome == "connected":
				var amount: int = int(weapon_damage.get(event.event_id, 0))
				var critical: String = " (крит)" if bool(event.result.get("critical", false)) else ""
				if String(event.payload.get("sword_abi_id", "")) == "ABI301":
					var abi_def: Dictionary = AbilityCatalog.definition(ability_definitions, "ABI301")
					result.append("%s — ABI «%s» атакует %s (%s): %d урона%s" % [from_name, String(abi_def.get("name", "Кровавый порез")), target_name, zone_name, amount, critical])
				else:
					result.append("%s атакует %s (%s): %d урона%s" % [from_name, target_name, zone_name, amount, critical])
			else:
				if String(event.payload.get("sword_abi_id", "")) == "ABI301":
					result.append("%s — ABI «Кровавый порез» атакует %s (%s): %s" % [from_name, target_name, zone_name, _attack_outcome(outcome)])
				else:
					result.append("%s атакует %s (%s): %s" % [from_name, target_name, zone_name, _attack_outcome(outcome)])
		elif root_id < 0 and event.kind == CombatEvent.Kind.DAMAGE and String(event.payload.get("source", "")) == "effect":
			result.append("EFF %s: %d урона %s" % [String(event.payload.get("effect_id", "")), int(event.result.get("hp_removed", 0)), _target(event.target_id, player_id)])
		elif root_id < 0 and event.kind == CombatEvent.Kind.EFFECT:
			if event.payload.has("inline_heal") and String(event.payload.get("source", "")) == "effect":
				result.append("EFF %s: +%d HP" % [String(event.payload.get("effect_id", "")), int(event.result.get("healed", 0))])
			elif event.parent_event_id >= 0 and bool(event.result.get("resolved", false)) and event.payload.has("effect_id"):
				result.append("%s: наложен %s" % [_actor(event.source_id, player_id), _effect_name(String(event.payload.get("effect_id", "")), effects_catalog)])
	return result

static func _ability_root_id(event: CombatEvent, by_id: Dictionary) -> int:
	var cursor: CombatEvent = event
	var depth: int = 0
	while cursor != null and depth < 32:
		if cursor.kind == CombatEvent.Kind.ACTION and String(cursor.payload.get("source_kind", "")) == "ability":
			return cursor.event_id
		if cursor.parent_event_id < 0 or not by_id.has(cursor.parent_event_id):
			return -1
		cursor = by_id[cursor.parent_event_id] as CombatEvent
		depth += 1
	return -1

static func _actor(combatant_id: String, player_id: String) -> String:
	return "Игрок" if combatant_id == player_id else "Противник"

static func _target(combatant_id: String, player_id: String) -> String:
	return "игрока" if combatant_id == player_id else "противника"

static func _effect_name(effect_id: String, definitions: Dictionary) -> String:
	var definition: Dictionary = EffectCatalog.definition(definitions, effect_id)
	var effect_name: String = String(definition.get("name", effect_id))
	return effect_name if effect_name == effect_id else "%s (%s)" % [effect_name, effect_id]

static func _attack_outcome(outcome: String) -> String:
	match outcome:
		"manual_block": return "ручной блок"
		"auto_block": return "отражено щитом"
		"dodge": return "уклонение"
		"miss", "magic_miss": return "промах"
		"stunned": return "оглушён"
		"source_dead": return "не может действовать"
		"target_dead": return "цель мертва"
		"connected": return "попадание"
		_: return outcome if not outcome.is_empty() else "не выполнено"

static func _ability_outcome(outcome: String) -> String:
	match outcome:
		"dispatched": return "без изменения HP или EFF"
		"magic_miss": return "промах"
		"stunned": return "оглушён"
		"source_dead": return "применение отменено: персонаж мёртв"
		"no_supported_components": return "нет применимых компонентов"
		_: return outcome if not outcome.is_empty() else "нет результата"

static func _zone_name(zone: String) -> String:
	match zone:
		"head": return "голова"
		"chest": return "грудь"
		"arms": return "руки"
		"waist": return "пояс"
		"legs": return "ноги"
		_: return zone

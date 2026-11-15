class_name AbilityCardText
extends RefCounted

## Read-only presentation for abilities shown on both equipped items and Arena.
## Never computes damage or mutates ability state.
static func describe(ability_id: String, definition: Dictionary, ap_available: int = -1) -> String:
	var lines: PackedStringArray = []
	match ability_id:
		"ABI401","ABI402","ABI403","ABI404","ABI405","ABI406","ABI407","ABI408","ABI409","ABI410","ABI411","ABI412","ABI701","ABI702","ABI703","ABI704":
			lines.append(String(definition.get("description","")))
			if float(definition.get("base_damage",0.0)) > 0.0:
				lines.append("Урон: база + усиление за каждые 10 уровней + %.2f × бонус силы атаки." % float(definition.get("attack_power_coefficient",0.0)))
		"ABI301","ABI302","ABI303","ABI304","ABI305","ABI306","ABI307","ABI308","ABI309","ABI310","ABI311","ABI312","ABI313","ABI314","ABI315","ABI316":
			lines.append(String(definition.get("description","")))
			if float(definition.get("attack_power_coefficient",0.0)) > 0.0:
				lines.append("Урон: числовое значение ранга I–X + бонус силы атаки.")
		"ABI501","ABI502","ABI503","ABI504","ABI505","ABI506","ABI507","ABI508","ABI509","ABI510","ABI511","ABI512","ABI513","ABI514","ABI515","ABI516":
			lines.append(String(definition.get("description","")))
			if float(definition.get("attack_power_coefficient",0.0)) > 0.0:
				lines.append("Урон: числовое значение ранга I–X + бонус силы атаки.")
		"ABI601","ABI602","ABI603","ABI604","ABI605","ABI606","ABI607","ABI608":
			lines.append(String(definition.get("description","")))
			if float(definition.get("attack_power_coefficient",0.0)) > 0.0:
				lines.append("Урон: числовое значение ранга I–X + бонус силы атаки.")
		_:
			for component in Array(definition.get("components", [])):
				if not component is Dictionary:
					continue
				var kind := String(component.get("kind", ""))
				if kind == "damage":
					lines.append("Урон: %s (%s)" % [str(component.get("amount", 0)), String(component.get("damage_type", "физический"))])
				elif kind == "heal":
					lines.append("Восстановление HP: %s" % str(component.get("amount", 0)))
				if kind in ["damage","heal"] and float(component.get("spell_power_scale",0.0))>0.0:
					lines.append("Масштабирование SP: база + %.3f × SP" % float(component.get("spell_power_scale",0.0)))
				if kind == "effect":
					var eff_id := String(component.get("effect_id", ""))
					var effect := EffectCatalog.definition(EffectCatalog.load_json(), eff_id)
					lines.append("Эффект: %s (%s)" % [String(effect.get("name", eff_id)), eff_id])
	var ap: String = str(int(definition.get("ap_cost", 0)))
	if bool(definition.get("consume_all_ap", false)):
		ap = "все доступные" if ap_available < 0 else "%d (все доступные)" % ap_available
	lines.append("AP: %s · Мана: %d · Перезарядка: %d раунд(ов)" % [ap, int(definition.get("mana_cost", 0)), int(definition.get("cooldown_rounds", 0))])
	return "\n".join(lines)

static func title(ability_id: String, definition: Dictionary) -> String:
	return "%s — %s" % [ability_id, String(definition.get("name", ability_id))]

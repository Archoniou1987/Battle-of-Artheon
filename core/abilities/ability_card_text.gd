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
		"ABI601":
			lines.append("Обычная MH-атака +20% урона. Формально снижает Tempo цели на 25% (стан пока не подключён). +1 AP.")
		"ABI602":
			lines.append("Отражает 20% входящего урона атакующему в текущем раунде. +1 AP.")
			lines.append("Пассивно: +1 заряд за каждое событие полученного урона; +5 за успешную MH, +5 дополнительно за крит MH.")
			lines.append("Макс 100 зарядов, не исчезают. Каждый даёт +0,25% брони и сопротивлений.")
		"ABI603":
			lines.append("Поглощает 50% зарядов. Восстанавливает n/2% максимального HP, n = потраченные заряды.")
		"ABI604":
			lines.append("Удар MH +100%. Поглощает все заряды.")
			lines.append("При попадании снижает броню выбранной зоны на n% на округлённые n/10 раундов.")
			lines.append("Если длительность округляется до 0, броня не снижается.")
		"ABI605":
			lines.append("Поглощает 25% зарядов. На 2 раунда +n% исходящего урона и 20% вампиризма.")
			lines.append("n — количество поглощённых зарядов.")
		"ABI606":
			lines.append("Поглощает все заряды. Урон 3% MH за каждый (до 300%).")
			lines.append("Формально снижает Tempo на 2 за заряд (до −200); оглушение будет подключено позже.")
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

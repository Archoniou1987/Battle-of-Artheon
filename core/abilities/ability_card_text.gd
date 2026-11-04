class_name AbilityCardText
extends RefCounted

## Read-only presentation for abilities shown on both equipped items and Arena.
## Never computes damage or mutates ability state.
static func describe(ability_id: String, definition: Dictionary, ap_available: int = -1) -> String:
	var lines: PackedStringArray = []
	match ability_id:
		"ABI301":
			lines.append("Усиливает обычную атаку MH на +%d урона без дополнительного удара." % int(definition.get("mh_flat_bonus", 0)))
			lines.append("При попадании: +1 AP и 1 стак кровотечения.")
		"ABI302":
			lines.append("До 3 целей: отдельный удар по 50% урона MH.")
			lines.append("При попадании: 1 стак кровотечения; +2 AP один раз за применение.")
		"ABI303":
			lines.append("Удар 50% MH. При попадании: −5% исходящего физического урона за каждый стак кровотечения на цели, 2 раунда.")
		"ABI304":
			lines.append("Удар 60% MH. При попадании: −1–5% антиизворотливости за каждый стак кровотечения на цели, 2 раунда (зависит от уровня EFF).")
		"ABI305":
			lines.append("Удар 75% MH. При попадании: −1–5% антикрита за каждый стак кровотечения на цели, 2 раунда (зависит от уровня EFF).")
		"ABI306":
			lines.append("Удар: 50% MH + 2% суммы брони пяти зон за каждый потраченный AP.")
			lines.append("При попадании: 1 стак кровотечения.")
		"ABI307":
			lines.append("До 5 целей: 25% MH × потраченные AP по каждой цели.")
			lines.append("При попадании: до 5 стаков кровотечения на цель.")
		"ABI308":
			lines.append("Удар MH: +10 п.п. шанса крита и +25% критического урона за AP.")
			lines.append("При попадании: 3 дополнительных тика текущего кровотечения, без расхода стаков.")
		"ABI401":
			lines.append("Отдельный удар: 20% MH. При попадании +1 AP, 1 стак пробитой брони (−3% брони, до 5).")
		"ABI402":
			lines.append("На 5 раундов: обычные MH/OH удары накладывают яд (до 10 стаков, 1 урон за стак/раунд).")
			lines.append("+1 AP при активации; каждый успешный стак яда имеет 5% шанс дать +1 AP.")
		"ABI403":
			lines.append("После уклонения в предыдущем раунде: до 5 соседних целей получают средний урон MH+OH.")
		"ABI404":
			lines.append("Удары MH+OH с +10% урона за стак яда на цели (макс +100%).")
			lines.append("На 2 раунда +5% уклонения за стак пробитой брони цели (до +25%).")
		"ABI405":
			lines.append("MH+OH. Перед атаками текущего раунда и на следующий: −50% уклонения и антикрита цели.")
		"ABI406":
			lines.append("По одному удару на текущий стак яда (макс 10): чередование MH/OH по 60% среднего урона.")
			lines.append("Без OH каждый второй удар имеет нулевой урон.")
		"ABI407":
			lines.append("50% среднего урона MH за стак пробитой брони (до 250%).")
			lines.append("При попадании добавляет 1 стак пробитой брони после расчёта удара.")
		"ABI408":
			lines.append("MH+OH. За каждый стак пробитой брони цель теряет 20% брони только против этой ABI.")
			lines.append("Стаки расходуются при успешном попадании хотя бы одним клинком.")
		_:
			for component in Array(definition.get("components", [])):
				if not component is Dictionary:
					continue
				var kind := String(component.get("kind", ""))
				if kind == "damage":
					lines.append("Урон: %s (%s)" % [str(component.get("amount", 0)), String(component.get("damage_type", "физический"))])
				elif kind == "heal":
					lines.append("Восстановление HP: %s" % str(component.get("amount", 0)))
				elif kind == "effect":
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

class_name EffectPolarity
extends RefCounted

## Canonical BUFF/DEBUFF classification used by dispel, Arena and diagnostics.
## Content may explicitly override inferred kind for unusual positive/negative EFF.
static func of(definition: Dictionary) -> String:
	var declared := String(definition.get("dispel_polarity", "")).to_upper()
	if declared in ["BUFF", "DEBUFF"]:
		return declared
	match String(definition.get("kind","")).to_lower():
		"hot", "buff", "shield", "regen", "regeneration":
			return "BUFF"
		"dot", "debuff", "stun", "freeze", "fear", "root", "slow", "poison", "bleed":
			return "DEBUFF"
	return ""

static func is_beneficial(definition: Dictionary) -> bool:
	return of(definition) == "BUFF"

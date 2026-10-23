class_name CombatDamagePayload
extends RefCounted

const PHYSICAL_DAMAGE_TYPES := ["physical","slashing","piercing","chopping","blunt"]
const MAGIC_DAMAGE_TYPES := ["fire","water","frost","air","earth","dark","light","lightning"]

static func is_physical_damage_type(damage_type:String) -> bool:
	return PHYSICAL_DAMAGE_TYPES.has(damage_type.to_lower())

static func is_magic_damage_type(damage_type:String) -> bool:
	return MAGIC_DAMAGE_TYPES.has(damage_type.to_lower())

static func defence_flags(damage_type:String, overrides:Dictionary={}) -> Dictionary:
	var flags := {
		"uses_physical_block": is_physical_damage_type(damage_type),
		"bypass_physical_mitigation": not is_physical_damage_type(damage_type)
	}
	for key in overrides:
		flags[key] = overrides[key]
	return flags

static func ability_attack_payload(parent:CombatEvent, component:Dictionary, amount:float, scale:float) -> Dictionary:
	var damage_type := String(component.get("damage_type", "physical"))
	var payload := {
		"raw_damage": amount,
		"uses_magic_hit": bool(parent.payload.get("uses_magic_hit", false)),
		"magic_hit_modifier": float(parent.payload.get("magic_hit_modifier", 0.0)),
		"magic_hit_roll": int(parent.payload.get("magic_hit_roll", 1)),
		"hit_already_resolved": bool(parent.payload.get("uses_magic_hit", false)),
		"magic_rating_applied": is_magic_damage_type(damage_type),
		"damage_type": damage_type,
		"zone": String(component.get("zone", parent.payload.get("zone", "chest"))),
		"rolls": parent.payload.get("rolls", {}),
		"source": "ability",
		"source_kind": "ability",
		"ability_id": String(parent.payload.get("ability_id", "")),
		"delivery_type": String(parent.payload.get("delivery_type", "DIRECT")),
		"min_zone_distance": int(parent.payload.get("min_zone_distance", 0)),
		"max_zone_distance": int(parent.payload.get("max_zone_distance", 2)),
		"two_zone_hit_modifier": float(parent.payload.get("two_zone_hit_modifier", -50.0)),
		"generates_ap": false,
		"aoe_scale": scale
	}
	payload.merge(defence_flags(damage_type), true)
	return payload

static func direct_damage_payload(parent:CombatEvent, damage_type:String, amount:float, source:String="ability") -> Dictionary:
	return {
		"amount": amount,
		"raw_damage": amount,
		"damage_type": damage_type,
		"source": source,
		"ability_id": String(parent.payload.get("ability_id", "")),
		"delivery_type": String(parent.payload.get("delivery_type", "DIRECT"))
	}

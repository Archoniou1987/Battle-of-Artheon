class_name PhysicalDamageBenchmarkParProfiles
extends RefCounted

## TEST ONLY: final effective archetype PAR percentages for Combat Engine.
## These are synthetic benchmark profiles, not character progression builds.
## The weapon still comes from the canonical v1.2 generator.
const CRIT_SPECIALISTS := ["SWORD_CRIT","DAGGER_ATTACK","AXE_ATTACK","AXE_DEF","2H_AXE","2H_SWORD"]
const DODGE_SPECIALISTS := ["SWORD_DODGE","DAGGER_DEF","DAGGER_ATTACK","DAGGER_PEN","2H_SPEAR"]
const BLOCK_SPECIALISTS := ["SWORD_DEF","HAMMER_DEF"]
const PEN_SPECIALISTS := ["DAGGER_PEN","2H_SPEAR"]

static func percentages(archetype: String) -> Dictionary:
	return {
		"crit":40.0 if CRIT_SPECIALISTS.has(archetype) else 0.0,
		"dodge":40.0 if DODGE_SPECIALISTS.has(archetype) else 0.0,
		"auto_block":40.0 if BLOCK_SPECIALISTS.has(archetype) else 0.0,
		"armour_pen":25.0 if PEN_SPECIALISTS.has(archetype) else 0.0,
		"crit_power":50.0 if CRIT_SPECIALISTS.has(archetype) else 0.0
	}

static func apply(actor: CombatantState, archetype: String) -> void:
	if actor==null:
		return
	var p := percentages(archetype)
	# Converted runtime percentage keys are consumed by the same canonical
	# CombatModifierService and CombatEngine calculations as ordinary fights.
	actor.combat_stats["crit_chance_rating_percent"]=float(p["crit"])
	actor.combat_stats["dodge_rating_percent"]=float(p["dodge"])
	actor.combat_stats["shield_auto_block_rating_percent"]=float(p["auto_block"])
	actor.combat_stats["crit_damage_rating_percent"]=float(p["crit_power"])
	# PAR126 is in percentage points (not 0..1); sync its snapshot and
	# derived runtime field, so all combat consumers agree.
	actor.combat_stats["armour_penetration_percent"]=float(p["armour_pen"])
	var totals: Dictionary = actor.combat_stats.get("par_totals",{}).duplicate(true)
	totals["PAR126"]=float(p["armour_pen"])
	actor.combat_stats["par_totals"]=totals

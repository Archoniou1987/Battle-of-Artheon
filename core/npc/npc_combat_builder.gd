class_name NpcCombatBuilder
extends RefCounted
static func build(npc:NpcState, combat_level:int=-1)->CombatantState:
	var level := npc.level if combat_level == -1 else combat_level
	var stats:Dictionary=(npc.base.get("stats",{}) as Dictionary).duplicate(true)
	var health:=int(npc.base.get("health",100+int(stats.get("PAR006",0))*10))
	var mana:=int(npc.base.get("mana",int(stats.get("PAR005",0))*15))
	var combatant:=CombatantState.new(npc.npc_id,npc.display_name,level,health,mana)
	combatant.stats=stats
	combatant.combat_stats=(npc.base.get("combat_stats",{}) as Dictionary).duplicate(true)
	combatant.combat_stats["par_totals"] = (npc.base.get("par_totals", {}) as Dictionary).duplicate(true)
	combatant.combat_stats["par_attack_ranges"] = (npc.base.get("par_attack_ranges", {}) as Dictionary).duplicate(true)
	for id in ParCombatContract.RATINGS:
		if not combatant.combat_stats["par_totals"].has(id):
			push_error("NPC missing canonical rating: " + npc.npc_id + ": " + id)
			return null
		combatant.combat_stats[ParCombatContract.RATINGS[id]] = combatant.combat_stats["par_totals"][id]
	var converted := CharacterStatsService.convert_ratings(combatant.combat_stats, level)
	if converted.is_empty():
		return null
	combatant.combat_stats = converted
	var contract := ParAttackContract.validate(combatant)
	if not bool(contract.ok):
		push_error("NPC PAR contract rejected: " + npc.npc_id + ": " + String(contract.reason))
		return null
	combatant.armour=(npc.base.get("armour",{}) as Dictionary).duplicate(true)
	combatant.combat_stats["abilities"]=npc.abilities.duplicate(true)
	return combatant

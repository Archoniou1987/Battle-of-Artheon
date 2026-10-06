class_name NpcCombatBuilder
extends RefCounted
static func build(npc:NpcState)->CombatantState:
	var stats:Dictionary=(npc.base.get("stats",{}) as Dictionary).duplicate(true)
	var health:=int(npc.base.get("health",100+int(stats.get("END",0))*10))
	var mana:=int(npc.base.get("mana",int(stats.get("WIS",0))*15))
	var combatant:=CombatantState.new(npc.npc_id,npc.display_name,npc.level,health,mana)
	combatant.stats=stats
	combatant.combat_stats=(npc.base.get("combat_stats",{}) as Dictionary).duplicate(true)
	combatant.armour=(npc.base.get("armour",{}) as Dictionary).duplicate(true)
	combatant.combat_stats["abilities"]=npc.abilities.duplicate(true)
	return combatant

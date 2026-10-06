class_name MapEncounterCombatService
extends RefCounted

static func begin(encounter:Dictionary,npc_repository:NpcRepository,player:CombatantState)->Dictionary:
	if not bool(encounter.get("ok",false)): return {"ok":false,"reason":"invalid_encounter"}
	var instance:NpcInstance=encounter.get("npc") as NpcInstance
	if instance==null: return {"ok":false,"reason":"missing_npc_instance"}
	var template:=npc_repository.get_npc(instance.template_id)
	if template==null: return {"ok":false,"reason":"missing_npc_template"}
	var enemy:=NpcCombatBuilder.build(template)
	enemy.combatant_id=instance.instance_id
	enemy.display_name=instance.display_name
	enemy.level=instance.level
	var state:=CombatState.new()
	state.add_combatant(player)
	state.add_combatant(enemy)
	return {"ok":true,"state":state,"player":player,"enemy":enemy,"npc":instance,"npc_instance_id":instance.instance_id,"npc_template_id":instance.template_id}

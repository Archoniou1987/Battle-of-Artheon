class_name MapEncounterCombatService
extends RefCounted

static func begin(encounter:Dictionary,npc_repository:NpcRepository,player:CombatantState)->Dictionary:
	if not bool(encounter.get("ok",false)):
		return {"ok":false,"reason":"invalid_encounter"}
	var instances:Array[NpcInstance]=[]
	var raw_group:Array=encounter.get("npcs",[])
	for raw_instance in raw_group:
		var group_instance:=raw_instance as NpcInstance
		if group_instance!=null and group_instance.is_alive():
			instances.append(group_instance)
	if instances.is_empty():
		var fallback:=encounter.get("npc") as NpcInstance
		if fallback!=null and fallback.is_alive():
			instances.append(fallback)
	if instances.is_empty():
		return {"ok":false,"reason":"missing_npc_instance"}

	var state:=CombatState.new()
	state.add_combatant(player)
	var enemies:Array[CombatantState]=[]
	var npc_instance_ids:Array[String]=[]
	var npc_template_ids:Array[String]=[]
	for instance in instances:
		var template:=npc_repository.get_npc(instance.template_id)
		if template==null:
			return {"ok":false,"reason":"missing_npc_template","npc_instance_id":instance.instance_id}
		var enemy:=NpcCombatBuilder.build(template)
		enemy.combatant_id=instance.instance_id
		enemy.display_name=instance.display_name
		enemy.level=instance.level
		state.add_combatant(enemy)
		enemies.append(enemy)
		npc_instance_ids.append(instance.instance_id)
		npc_template_ids.append(instance.template_id)

	var group:=GroupCombatState.new(state)
	group.add_member("players",player.combatant_id)
	for enemy in enemies:
		group.add_member("enemies",enemy.combatant_id)
	var controller:=GroupCombatController.new(group)
	controller.initialize_active_opponents()

	var primary:NpcInstance=instances[0]
	var primary_enemy:CombatantState=enemies[0]
	return {
		"ok":true,
		"state":state,
		"group":group,
		"group_controller":controller,
		"player":player,
		"enemy":primary_enemy,
		"enemies":enemies,
		"npc":primary,
		"npcs":instances,
		"npc_instance_id":primary.instance_id,
		"npc_template_id":primary.template_id,
		"npc_instance_ids":npc_instance_ids,
		"npc_template_ids":npc_template_ids
	}

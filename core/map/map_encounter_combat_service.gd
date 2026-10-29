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
		var enemy:=NpcCombatBuilder.build(template, instance.level)
		if enemy == null:
			return {"ok":false,"reason":"invalid_npc_par_contract","npc_instance_id":instance.instance_id}
		enemy.combatant_id=instance.instance_id
		enemy.display_name=instance.display_name
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

## Opt-in resumable world encounter. The encounter key must identify a
## particular world/map/NPC cohort, not just the NPC template. Existing
## begin() callers keep their in-memory behavior.
static func begin_resumable(encounter: Dictionary, npc_repository: NpcRepository, player: CombatantState, encounter_key: String, path: String = GroupCombatCheckpointService.DEFAULT_PATH) -> Dictionary:
	if not GroupCombatCheckpointService._valid_identity(encounter_key, "0".repeat(64)) or not GroupCombatCheckpointService._valid_path(path):
		return {"ok":false,"reason":"invalid_checkpoint_context"}
	# Rebuild the canonical roster from the current world. This is the
	# authoritative owner/gear fingerprint for checking a suspended fight.
	var opened: Dictionary = begin(encounter,npc_repository,player)
	if not bool(opened.get("ok",false)):
		return opened
	var fingerprint := GroupCombatCheckpointService.initial_roster_fingerprint(opened["state"])
	if fingerprint.is_empty():
		return {"ok":false,"reason":"invalid_roster_fingerprint"}
	var simulator: GroupCombatSimulator
	var resumed := false
	if FileAccess.file_exists(path):
		var loaded: Dictionary = GroupCombatCheckpointService.read(path,encounter_key,fingerprint)
		if not bool(loaded.get("ok",false)):
			# Do NOT silently start a fresh encounter on an invalid or stale
			# save: that would re-roll combat/loot and bypass old damage.
			return {"ok":false,"reason":String(loaded.get("reason","checkpoint_invalid"))}
		simulator = loaded["simulator"]
		resumed = true
	else:
		simulator = GroupCombatSimulator.new(opened["state"],opened["group"])
	var configured: Dictionary = simulator.enable_checkpoint(encounter_key,fingerprint,path)
	if not bool(configured.get("ok",false)):
		return configured
	# Bind returned combat objects to the restored state, while retaining
	# the original world NPC references for later MapCombatOutcomeService.
	opened["simulator"] = simulator
	opened["state"] = simulator.state
	opened["group"] = simulator.group
	opened["group_controller"] = simulator.controller
	opened["player"] = simulator.state.get_combatant(player.combatant_id)
	opened["enemy"] = simulator.state.get_combatant(String(opened["npc_instance_id"]))
	var restored_enemies: Array[CombatantState] = []
	for raw_id in Array(opened["npc_instance_ids"]):
		var target := simulator.state.get_combatant(String(raw_id))
		if target == null:
			return {"ok":false,"reason":"restored_npc_missing"}
		restored_enemies.append(target)
	opened["enemies"] = restored_enemies
	opened["resumed"] = resumed
	opened["checkpoint_path"] = path
	opened["checkpoint_round"] = simulator.state.round_number
	opened["checkpoint_terminal"] = simulator.controller.combat_finished()
	return opened

## Caller should invoke only after world death/loot outcome is durably
## committed; terminal checkpoints otherwise remain available for recovery.
static func acknowledge_resolved_encounter(path: String = GroupCombatCheckpointService.DEFAULT_PATH) -> bool:
	return GroupCombatCheckpointService.clear(path)

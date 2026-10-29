class_name GeneratedMapPopulationService
extends RefCounted

## Converts the ONE canonical LocationGenerator output into live combat NPCs.
## The generator's own entities are placeholders, never a second NPC owner.
## No data is saved here; caller owns the one ExpeditionState/GameState.
static func populate(generated: Dictionary, expedition: ExpeditionState, catalog: NpcRepository) -> Dictionary:
	var map: TacticalMapState = generated.get("map",null)
	if map == null or expedition == null or catalog == null:
		return {"ok":false,"reason":"generated_population_invalid_input"}
	var bridge := MapNpcBridge.new()
	var entries: Array[Dictionary] = []
	for i in range(Array(generated.get("npc_cells",[])).size()):
		var cell: Vector2i = generated["npc_cells"][i]
		entries.append({"id":"GEN_NPC_%02d"%i,"template":"NPC001" if i%3==0 else ("NPC003" if i%3==1 else "NPC004"),"cell":cell})
	for entry in generated.get("region_npcs",[]):
		var region_type := String(entry.get("region_type",""))
		var template := "NPC003" if region_type=="bandit_camp" else ("NPC001" if region_type=="beast_den" else "NPC004")
		entries.append({"id":String(entry["entity_id"]),"template":template,"cell":entry["pos"]})
	for guard in generated.get("guarded_objects",[]):
		entries.append({"id":String(guard["guard_id"]),"template":"NPC003","cell":guard["guard_pos"]})
	for guard in generated.get("route_guards",[]):
		entries.append({"id":String(guard["guard_id"]),"template":"NPC003","cell":guard["guard_pos"]})
	for patrol in generated.get("patrols",[]):
		entries.append({"id":String(patrol["patrol_id"]),"template":"NPC001" if String(patrol.get("region_type",""))=="beast_den" else "NPC003","cell":patrol["start"]})
	for boss in generated.get("boss_groups",[]):
		entries.append({"id":String(boss["boss_id"]),"template":"NPC005","cell":boss["boss_pos"]})
		var guards: Array = boss.get("guard_ids",[])
		var cells: Array = boss.get("guard_positions",[])
		for i in range(guards.size()):
			entries.append({"id":String(guards[i]),"template":"NPC003","cell":cells[i]})
	var ids: Dictionary = {}
	for entry in entries:
		var id := String(entry["id"])
		if ids.has(id):
			return {"ok":false,"reason":"generated_duplicate_npc_id","id":id}
		ids[id]=true
		var cell: Vector2i = entry["cell"]
		if not map.in_bounds(cell) or not map.cell(cell).is_passable():
			return {"ok":false,"reason":"generated_npc_cell_invalid","id":id}
		if not map.entity_positions.has(id) or map.entity_positions[id]!=cell:
			return {"ok":false,"reason":"generated_npc_placement_mismatch","id":id}
		var template: NpcState = catalog.get_npc(String(entry["template"]))
		if template == null:
			return {"ok":false,"reason":"generated_npc_template_missing","id":id}
	# Remove ONLY generator placeholders to avoid a phantom entity roster.
	# Real NPC objects are registered by the existing production MapNpcBridge.
	for entry in entries:
		map.remove_entity(String(entry["id"]))
	for entry in entries:
		var id := String(entry["id"])
		if MapWorldCommitService.is_defeated_spawn(expedition,id):
			continue
		var npc := NpcInstance.new(id,catalog.get_npc(String(entry["template"])))
		if not bridge.register_npc(map,npc,entry["cell"]):
			return {"ok":false,"reason":"generated_npc_registration_failed","id":id}
	return {"ok":true,"map":map,"bridge":bridge,"npc_count":bridge.instances.size()}

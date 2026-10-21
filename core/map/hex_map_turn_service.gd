class_name HexMapTurnService
extends RefCounted

var coordinator:HexEncounterCoordinator=HexEncounterCoordinator.new()

func move_player(map:TacticalMapState,bridge:MapNpcBridge,player_id:String,to:Vector2i,rng:RandomNumberGenerator)->Dictionary:
	if coordinator.combat_active:
		return {"ok":false,"reason":"combat_active"}
	if map==null or bridge==null or rng==null:
		return {"ok":false,"reason":"invalid_context"}
	var moved:=map.move_entity(player_id,to)
	if not bool(moved.get("ok",false)):
		return moved
	var encounter:=coordinator.try_start(map,bridge,player_id,rng)
	if bool(encounter.get("ok",false)):
		return {"ok":true,"movement":moved,"encounter":encounter}
	return {"ok":true,"movement":moved}

func step_patrol(map:TacticalMapState,bridge:MapNpcBridge,patrol:HexPatrolState,player_id:String,rng:RandomNumberGenerator,elapsed_seconds:float=1.0)->Dictionary:
	if map==null or bridge==null or patrol==null or rng==null:
		return {"ok":false,"reason":"invalid_context"}
	var result:=patrol.step(map,coordinator.combat_active,elapsed_seconds,player_id)
	if result.get("reason","")=="player_contact":
		var encounter:=coordinator.try_start_patrol_contact(map,bridge,player_id,patrol.patrol_id,rng)
		if bool(encounter.get("ok",false)):
			return {"ok":true,"patrol_contact":result,"encounter":encounter}
	return result

func step_chase(map:TacticalMapState,bridge:MapNpcBridge,chase:HexNpcChaseState,player_id:String,rng:RandomNumberGenerator)->Dictionary:
	if chase==null:
		return {"ok":false,"reason":"invalid_chase"}
	var result:=chase.step(map,bridge,player_id,rng,coordinator.combat_active)
	if bool(result.get("contact",false)):
		var encounter:=coordinator.try_start_patrol_contact(map,bridge,player_id,chase.npc_id,rng)
		if bool(encounter.get("ok",false)):
			return {"ok":true,"chase":result,"encounter":encounter}
	return result

func resolve_group_victory(result:Dictionary,map:TacticalMapState,bridge:MapNpcBridge,encounter:Dictionary,player:CharacterState,repository:ItemRepository,loot_service:NpcPossessionLootService,quality_chances:Dictionary)->Dictionary:
	if not coordinator.combat_active:
		return {"ok":false,"reason":"no_active_combat"}
	if not bool(encounter.get("ok",false)):
		return {"ok":false,"reason":"invalid_encounter"}
	var npcs:Array[NpcInstance]=[]
	for raw_npc in encounter.get("npcs",[]):
		var npc:=raw_npc as NpcInstance
		if npc!=null:
			npcs.append(npc)
	var outcome:=MapCombatOutcomeService.resolve_group_victory(result,map,bridge,npcs,player,repository,loot_service,quality_chances)
	if bool(outcome.get("ok",false)):
		coordinator.finish_combat()
	return outcome

## World-map opt-in route. Map contact and patrol/chase movement are
## handled by the existing HexEncounterCoordinator; the combat state is
## still owned by MapEncounterCombatService / GroupCombatSimulator.
func begin_resumable_group_combat(encounter: Dictionary, repository: NpcRepository, fighter: CombatantState, encounter_key: String, checkpoint_path: String = GroupCombatCheckpointService.DEFAULT_PATH) -> Dictionary:
	if not coordinator.combat_active and not FileAccess.file_exists(checkpoint_path):
		return {"ok":false,"reason":"no_active_map_encounter"}
	var opened: Dictionary = MapEncounterCombatService.begin_resumable(encounter,repository,fighter,encounter_key,checkpoint_path)
	if bool(opened.get("ok",false)):
		coordinator.combat_active = true
	return opened

## Maps may progress after the outcome journal is durable and applied,
## but the calling game state still MUST persist the expedition/repository
## and acknowledge the journal in a later step.
func resolve_group_victory_durable(session: Dictionary, expedition: ExpeditionState, map: TacticalMapState, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository, loot_service: NpcPossessionLootService, quality_chances: Dictionary, encounter_key: String, receipt_path: String = MapCombatSettlementService.DEFAULT_PATH, now_unix: int = -1) -> Dictionary:
	if not coordinator.combat_active:
		return {"ok":false,"reason":"no_active_combat"}
	var result: Dictionary = MapCombatSettlementService.settle(session,expedition,map,bridge,player,repository,loot_service,quality_chances,encounter_key,receipt_path,now_unix)
	if bool(result.get("ok",false)):
		coordinator.finish_combat()
	return result

## On restart a world may be reconstructed with every NPC alive again.
## Reapply the immutable journal before map movement/patrol simulation.
func recover_settled_group_victory(receipt_path: String, encounter_key: String, expedition: ExpeditionState, map: TacticalMapState, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository) -> Dictionary:
	var result: Dictionary = MapCombatSettlementService.apply(receipt_path,encounter_key,expedition,map,bridge,player,repository)
	if bool(result.get("ok",false)):
		coordinator.finish_combat()
	return result

## Fully committed world-map completion: keep the coordinator's
## movement/patrol pause until the combat reward, player resources and
## single atomic expedition/inventory snapshot are verified on disk.
## The older resolve_group_victory_durable() remains available for callers
## managing their own snapshot/acknowledgement workflow.
func finalize_group_victory_atomic(session: Dictionary, encounter_key: String, expedition: ExpeditionState, map: TacticalMapState, bridge: MapNpcBridge, player: CharacterState, repository: ItemRepository, loot_service: NpcPossessionLootService, quality_chances: Dictionary, receipt_path: String = MapCombatSettlementService.DEFAULT_PATH, checkpoint_path: String = GroupCombatCheckpointService.DEFAULT_PATH, world_snapshot_path: String = MapWorldCommitService.DEFAULT_PATH, now_unix: int = -1) -> Dictionary:
	if not coordinator.combat_active:
		return {"ok":false,"reason":"no_active_combat"}
	var simulator: GroupCombatSimulator = session.get("simulator") as GroupCombatSimulator
	if simulator == null or player == null or repository == null:
		return {"ok":false,"reason":"missing_atomic_combat_owner"}
	if String(session.get("checkpoint_path","")) != checkpoint_path:
		return {"ok":false,"reason":"atomic_checkpoint_path_mismatch"}
	var resolved: Dictionary = MapCombatSettlementService.settle(session,expedition,map,bridge,player,repository,loot_service,quality_chances,encounter_key,receipt_path,now_unix)
	if not bool(resolved.get("ok",false)):
		return {"ok":false,"reason":"world_settlement_failed","detail":String(resolved.get("reason","unknown"))}
	# The canonical combatant (not the map-NPC or the Arena test avatar)
	# owns these resources. Failure retains the journals and map pause.
	var winner: CombatantState = simulator.state.get_combatant(player.character_id)
	if winner == null or not player.commit_combat_resources(winner,repository):
		return {"ok":false,"reason":"combat_resource_commit_failed"}
	var stored := MapWorldCommitService.commit(session,encounter_key,expedition,map,bridge,player,repository,receipt_path,checkpoint_path,world_snapshot_path)
	if not bool(stored.get("ok",false)):
		return {"ok":false,"reason":"atomic_world_commit_failed","detail":String(stored.get("reason","unknown"))}
	var acknowledgement := MapWorldCommitService.acknowledge(world_snapshot_path,receipt_path,checkpoint_path,encounter_key,expedition.expedition_id,player.character_id)
	if not bool(acknowledgement.get("ok",false)):
		return {"ok":false,"reason":"atomic_world_ack_failed","detail":String(acknowledgement.get("reason","unknown"))}
	coordinator.finish_combat()
	return {"ok":true,"world_snapshot_path":world_snapshot_path,"defeated_ids":resolved.get("defeated_ids",[]),"loot_pool":expedition.restore_loot_pool(encounter_key),"world_committed":true}

func finish_combat()->void:
	coordinator.finish_combat()

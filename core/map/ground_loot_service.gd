class_name GroundLootService
extends RefCounted

## Solo Final-v1: durable ground-item registry owned by ExpeditionState.
## This service never creates new ItemRepository instances and never rolls
## rewards. Callers supply an existing unowned instance ID (combat/quest loot)
## or move an item out of the player's bag.
const WORLD_KEY := "ground_item_instances"
const POLICY_EXPEDITION := "expedition"
const POLICY_TIMED := "timed"
const PICKUP_SECONDS := 5
const DEFAULT_MAX_SLOTS := -1
const DEFAULT_MAX_WEIGHT := -1.0

## In-progress pickup is deliberately ephemeral; after process restart it
## has to be started again. Item location remains fully persistent.
var pending_pickups: Dictionary = {}
var _serial: int = 0

static func _registry(expedition: ExpeditionState) -> Dictionary:
	return Dictionary(expedition.world_state.get(WORLD_KEY,{})).duplicate(true)

static func _valid_expedition(expedition: ExpeditionState) -> bool:
	return expedition != null and expedition.is_active() and not expedition.expedition_id.is_empty()

static func _weight(item: Dictionary) -> float:
	var value: Variant = item.get("weight",0.0)
	if not RatingMatrix._number(value) or not is_finite(float(value)) or float(value) < 0.0:
		return -1.0
	return float(value)

static func _capacity(player: CharacterState, repository: ItemRepository, maximum_slots: int, maximum_weight: float) -> Dictionary:
	if player == null or repository == null:
		return {"ok":false,"reason":"missing_inventory"}
	var used_weight := 0.0
	for owned_id in player.inventory.instance_ids():
		var owned := repository.get_item(String(owned_id))
		if owned.is_empty():
			return {"ok":false,"reason":"missing_owned_item"}
		var weight := _weight(owned)
		if weight < 0.0:
			return {"ok":false,"reason":"invalid_item_weight"}
		used_weight += weight
	var effective_slots := player.bag_capacity if maximum_slots < 0 else maximum_slots
	return {"ok":true,"used_slots":player.inventory.size(),"max_slots":effective_slots,"used_weight":used_weight,"max_weight":maximum_weight}

static func items_at(expedition: ExpeditionState, cell: Vector2i, player_id: String = "", now_unix: int = -1) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	if not _valid_expedition(expedition):
		return visible
	var registry := _registry(expedition)
	for id in registry:
		var entry: Dictionary = registry[id]
		var pos: Array = entry.get("cell",[])
		if pos.size() != 2 or Vector2i(int(pos[0]),int(pos[1])) != cell:
			continue
		if String(entry.get("owner_id","")) != "" and String(entry["owner_id"]) != player_id:
			continue
		if String(entry.get("policy","")) == POLICY_TIMED and now_unix >= 0 and now_unix >= int(entry.get("expires_at_unix",0)):
			continue
		visible.append(entry.duplicate(true))
	return visible

## This is the reward/quest/spawn adapter boundary. Source systems must
## guarantee the instance is not owned by an NPC/player or another container.
static func place_unowned(expedition: ExpeditionState, repository: ItemRepository, instance_id: String, cell: Vector2i, source_id: String, owner_id: String = "", policy: String = POLICY_EXPEDITION, expires_at_unix: int = 0) -> Dictionary:
	if not _valid_expedition(expedition) or repository == null or instance_id.is_empty() or not repository.has_item(instance_id):
		return {"ok":false,"reason":"invalid_ground_item"}
	if not [POLICY_EXPEDITION,POLICY_TIMED].has(policy) or (policy == POLICY_TIMED and expires_at_unix <= 0):
		return {"ok":false,"reason":"invalid_ground_lifetime"}
	var registry := _registry(expedition)
	if registry.has(instance_id):
		return {"ok":false,"reason":"already_on_ground"}
	registry[instance_id] = {"instance_id":instance_id,"cell":[cell.x,cell.y],"source_id":source_id,"owner_id":owner_id,"policy":policy,"expires_at_unix":expires_at_unix}
	expedition.world_state[WORLD_KEY] = registry
	return {"ok":true,"instance_id":instance_id}

## Dropping an item on a map transfers exactly the same instance ID from
## the player's BAG to the ground. Equipped items must be unequipped first.
static func drop_from_bag(expedition: ExpeditionState, map: TacticalMapState, player: CharacterState, repository: ItemRepository, instance_id: String) -> Dictionary:
	if not _valid_expedition(expedition) or map == null or player == null or repository == null or player.in_combat:
		return {"ok":false,"reason":"invalid_drop_context"}
	if not map.entity_positions.has(player.character_id):
		return {"ok":false,"reason":"player_not_on_map"}
	if not player.inventory.owns(instance_id) or player.equipment.is_equipped(instance_id):
		return {"ok":false,"reason":"item_not_available_for_drop"}
	var cell: Vector2i = map.entity_positions[player.character_id]
	var registry := _registry(expedition)
	if registry.has(instance_id):
		return {"ok":false,"reason":"item_already_on_ground"}
	if not player.inventory.remove_instance(instance_id,player.equipment):
		return {"ok":false,"reason":"bag_drop_failed"}
	for index in range(player.elixir_slots.size()):
		if player.elixir_slots[index] == instance_id:
			player.elixir_slots[index] = ""
	registry[instance_id] = {"instance_id":instance_id,"cell":[cell.x,cell.y],"source_id":"player_drop","owner_id":"","policy":POLICY_EXPEDITION,"expires_at_unix":0}
	expedition.world_state[WORLD_KEY] = registry
	return {"ok":true,"instance_id":instance_id}

func begin_pickup(expedition: ExpeditionState, map: TacticalMapState, player: CharacterState, repository: ItemRepository, instance_id: String, started_at_unix: int) -> Dictionary:
	if not _valid_expedition(expedition) or map == null or player == null or repository == null or player.in_combat or started_at_unix < 0:
		return {"ok":false,"reason":"invalid_pickup_context"}
	if not map.entity_positions.has(player.character_id):
		return {"ok":false,"reason":"player_not_on_map"}
	var entry: Dictionary = _registry(expedition).get(instance_id,{})
	if entry.is_empty() or not repository.has_item(instance_id):
		return {"ok":false,"reason":"ground_item_not_found"}
	var pos: Array = entry.get("cell",[])
	if pos.size() != 2 or Vector2i(int(pos[0]),int(pos[1])) != map.entity_positions[player.character_id]:
		return {"ok":false,"reason":"pickup_requires_same_cell"}
	if String(entry.get("owner_id","")) != "" and String(entry.get("owner_id","")) != player.character_id:
		return {"ok":false,"reason":"not_your_ground_item"}
	if String(entry.get("policy","")) == POLICY_TIMED and started_at_unix >= int(entry.get("expires_at_unix",0)):
		return {"ok":false,"reason":"ground_item_expired"}
	if player.inventory.owns(instance_id) or player.equipment.is_equipped(instance_id):
		return {"ok":false,"reason":"already_owned"}
	_serial += 1
	var ticket := player.character_id + ":pickup:" + str(_serial)
	pending_pickups[ticket] = {"item_id":instance_id,"expedition_id":expedition.expedition_id,"player_id":player.character_id,"cell":pos.duplicate(),"began":started_at_unix}
	return {"ok":true,"ticket":ticket,"complete_at_unix":started_at_unix+PICKUP_SECONDS}

func cancel_pickup(ticket: String) -> bool:
	return pending_pickups.erase(ticket)

func finish_pickup(ticket: String, expedition: ExpeditionState, map: TacticalMapState, player: CharacterState, repository: ItemRepository, now_unix: int, maximum_slots: int = DEFAULT_MAX_SLOTS, maximum_weight: float = DEFAULT_MAX_WEIGHT) -> Dictionary:
	if not pending_pickups.has(ticket):
		return {"ok":false,"reason":"pickup_not_started"}
	var action: Dictionary = pending_pickups[ticket]
	if now_unix < int(action["began"]) + PICKUP_SECONDS:
		return {"ok":false,"reason":"pickup_still_running"}
	# The action cannot be replayed after a failed or successful completion.
	pending_pickups.erase(ticket)
	if not _valid_expedition(expedition) or map == null or player == null or repository == null or player.in_combat:
		return {"ok":false,"reason":"invalid_pickup_context"}
	if expedition.expedition_id != String(action["expedition_id"]) or player.character_id != String(action["player_id"]):
		return {"ok":false,"reason":"pickup_identity_mismatch"}
	if not map.entity_positions.has(player.character_id):
		return {"ok":false,"reason":"player_not_on_map"}
	var at: Vector2i = map.entity_positions[player.character_id]
	if [at.x,at.y] != action["cell"]:
		return {"ok":false,"reason":"pickup_interrupted_by_movement"}
	var item_id := String(action["item_id"])
	var registry := _registry(expedition)
	var entry: Dictionary = registry.get(item_id,{})
	if entry.is_empty() or entry.get("cell",[]) != action["cell"]:
		return {"ok":false,"reason":"pickup_item_unavailable"}
	if String(entry.get("owner_id","")) != "" and String(entry.get("owner_id","")) != player.character_id:
		return {"ok":false,"reason":"pickup_access_revoked"}
	if String(entry.get("policy","")) == POLICY_TIMED and now_unix >= int(entry.get("expires_at_unix",0)):
		return {"ok":false,"reason":"pickup_item_expired"}
	if player.inventory.owns(item_id) or not repository.has_item(item_id):
		return {"ok":false,"reason":"pickup_already_claimed"}
	var item := repository.get_item(item_id)
	var weight := _weight(item)
	if weight < 0.0:
		return {"ok":false,"reason":"pickup_invalid_weight"}
	var capacity := _capacity(player,repository,maximum_slots,maximum_weight)
	if not bool(capacity.get("ok",false)):
		return capacity
	if int(capacity["max_slots"]) >= 0 and int(capacity["used_slots"]) >= int(capacity["max_slots"]):
		return {"ok":false,"reason":"pickup_slots_full"}
	if float(capacity["max_weight"]) >= 0.0 and float(capacity["used_weight"]) + weight > float(capacity["max_weight"]) + 0.0001:
		return {"ok":false,"reason":"pickup_overweight"}
	if not player.inventory.add_instance(item_id,repository):
		return {"ok":false,"reason":"pickup_bag_transfer_failed"}
	registry.erase(item_id)
	expedition.world_state[WORLD_KEY] = registry
	return {"ok":true,"instance_id":item_id,"needs_world_save":true}

static func remove_expired(expedition: ExpeditionState, repository: ItemRepository, now_unix: int) -> int:
	if not _valid_expedition(expedition) or repository == null:
		return 0
	var registry := _registry(expedition)
	var removed := 0
	for id in registry.keys():
		var entry: Dictionary = registry[id]
		if String(entry.get("policy","")) == POLICY_TIMED and now_unix >= int(entry.get("expires_at_unix",0)):
			repository.remove_item(String(id))
			registry.erase(id)
			removed += 1
	expedition.world_state[WORLD_KEY] = registry
	return removed

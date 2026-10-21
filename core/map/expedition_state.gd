class_name ExpeditionState
extends RefCounted

const SOLO_START_CELL_KEY := "solo_start_cell_v1"
const STATUS_ACTIVE:="active"
const STATUS_COMPLETED:="completed"
const STATUS_EXITED:="exited"
const STATUS_EXPIRED:="expired"

var expedition_id:String
var profile:ExpeditionProfile
var seed_value:int
var status:String=STATUS_ACTIVE
var player_position:Vector2i=Vector2i.ZERO
var created_at_unix:int=0
var expires_at_unix:int=0
var world_state:Dictionary={}

func _init(p_expedition_id:String="",p_profile:ExpeditionProfile=null,p_seed_value:int=1)->void:
	expedition_id=p_expedition_id
	profile=p_profile if p_profile!=null else ExpeditionProfile.new()
	seed_value=p_seed_value

func is_active()->bool:
	return status==STATUS_ACTIVE

func final_expiration_unix()->int:
	if expires_at_unix<=0:
		return 0
	return expires_at_unix+profile.grace_period_seconds

func refresh_lifetime(now_unix:int)->Dictionary:
	if not is_active() or profile.lifetime_policy!=ExpeditionProfile.LIFETIME_TIME_LIMITED or expires_at_unix<=0:
		return {"expired":false}
	var deadline:=final_expiration_unix()
	if now_unix<deadline:
		return {"expired":false,"event_ended":now_unix>=expires_at_unix,"deadline":deadline}
	status=STATUS_EXPIRED
	return {"expired":true,"outcome":profile.expiration_outcome,"deadline":deadline}

func save_loot_pool(encounter_id:String,pool:EncounterLootPool)->bool:
	if encounter_id.is_empty() or pool==null: return false
	var pools:Dictionary=Dictionary(world_state.get("encounter_loot_pools",{})).duplicate(true)
	pools[encounter_id]=pool.to_dict()
	world_state["encounter_loot_pools"]=pools
	return true

func restore_loot_pool(encounter_id:String)->EncounterLootPool:
	var pools:Dictionary=world_state.get("encounter_loot_pools",{})
	if not pools.has(encounter_id): return null
	var data=pools[encounter_id]
	if not data is Dictionary: return null
	return EncounterLootPool.from_dict(data)

func remove_loot_pool(encounter_id:String)->bool:
	var pools:Dictionary=Dictionary(world_state.get("encounter_loot_pools",{})).duplicate(true)
	if not pools.has(encounter_id): return false
	pools.erase(encounter_id)
	world_state["encounter_loot_pools"]=pools
	return true

func loot_hexes_for_player(player_id:String,now_unix:int)->Array[Vector2i]:
	var cells:Array[Vector2i]=[]
	if player_id.is_empty():
		return cells
	var pools:Dictionary=world_state.get("encounter_loot_pools",{})
	for encounter_id in pools:
		var pool:=restore_loot_pool(String(encounter_id))
		if pool!=null and pool.has_visible_loot(now_unix) and not pool.available_for(player_id).is_empty() and not cells.has(pool.hex_cell):
			cells.append(pool.hex_cell)
	return cells

func loot_pools_for_player_at_hex(player_id:String,cell:Vector2i,now_unix:int)->Array[String]:
	var ids:Array[String]=[]
	if player_id.is_empty():
		return ids
	var pools:Dictionary=world_state.get("encounter_loot_pools",{})
	for encounter_id in pools:
		var pool:=restore_loot_pool(String(encounter_id))
		if pool!=null and pool.hex_cell==cell and pool.has_visible_loot(now_unix) and not pool.available_for(player_id).is_empty():
			ids.append(String(encounter_id))
	return ids

func loot_hexes(now_unix:int)->Array[Vector2i]:
	var cells:Array[Vector2i]=[]
	var pools:Dictionary=world_state.get("encounter_loot_pools",{})
	for encounter_id in pools:
		var pool:=restore_loot_pool(String(encounter_id))
		if pool!=null and pool.has_visible_loot(now_unix) and not cells.has(pool.hex_cell):
			cells.append(pool.hex_cell)
	return cells

func claim_loot_at_hex(player:CharacterState,cell:Vector2i,item_id:String,repository:ItemRepository,now_unix:int)->bool:
	if player==null or repository==null or item_id.is_empty():
		return false
	for encounter_id in loot_pools_for_player_at_hex(player.character_id,cell,now_unix):
		var pool:=restore_loot_pool(encounter_id)
		if pool==null or not pool.available_for(player.character_id).has(item_id):
			continue
		if not pool.claim(item_id,player,repository,now_unix):
			return false
		if pool.entries.is_empty():
			remove_loot_pool(encounter_id)
		else:
			save_loot_pool(encounter_id,pool)
		return true
	return false

func claim_all_loot_at_hex(player:CharacterState,cell:Vector2i,repository:ItemRepository,now_unix:int)->Array[String]:
	var claimed:Array[String]=[]
	if player==null or repository==null:
		return claimed
	for encounter_id in loot_pools_for_player_at_hex(player.character_id,cell,now_unix):
		var pool:=restore_loot_pool(encounter_id)
		if pool==null:
			continue
		for item_id in pool.available_for(player.character_id):
			if claim_loot_at_hex(player,cell,item_id,repository,now_unix):
				claimed.append(item_id)
	return claimed

func cleanup_expired_loot(now_unix:int,repository:ItemRepository)->int:
	# Never discard pool ownership records without a repository to clean up instances.
	if repository==null:
		return 0
	var removed:=0
	var pools:Dictionary=Dictionary(world_state.get("encounter_loot_pools",{})).duplicate(true)
	for encounter_id in pools.keys():
		var pool:=restore_loot_pool(String(encounter_id))
		if pool==null:
			continue
		if pool.is_expired(now_unix):
			pool.expire(now_unix,repository)
			pools.erase(encounter_id)
			removed+=1
	world_state["encounter_loot_pools"]=pools
	return removed

func to_dict()->Dictionary:
	return {
		"expedition_id":expedition_id,
		"profile":profile.to_dict(),
		"seed_value":seed_value,
		"status":status,
		"player_position":[player_position.x,player_position.y],
		"created_at_unix":created_at_unix,
		"expires_at_unix":expires_at_unix,
		"world_state":world_state.duplicate(true)
	}

static func from_dict(data:Dictionary)->ExpeditionState:
	var restored:=ExpeditionState.new(
		String(data.get("expedition_id","")),
		ExpeditionProfile.from_dict(data.get("profile",{})),
		int(data.get("seed_value",1))
	)
	restored.status=String(data.get("status",STATUS_ACTIVE))
	var pos:Array=data.get("player_position",[0,0])
	if pos.size()>=2:
		restored.player_position=Vector2i(int(pos[0]),int(pos[1]))
	restored.created_at_unix=int(data.get("created_at_unix",0))
	restored.expires_at_unix=int(data.get("expires_at_unix",0))
	restored.world_state=Dictionary(data.get("world_state",{})).duplicate(true)
	return restored

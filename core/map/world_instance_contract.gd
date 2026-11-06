class_name WorldInstanceContract
extends RefCounted

## Shared data contract for Solo and future server-owned MP maps.
## No storage implementation and no character copy belongs to a map.
const VERSION := 1
const AUTHORITY_LOCAL := "local"
const AUTHORITY_SERVER := "server"
const POLICY_SAFE := "safe"
const POLICY_OPEN_PVP := "open_pvp"
const STATE_ACTIVE := "active"
const STATE_IDLE := "idle"
const STATE_CLOSED := "closed"

static func settlement(id: String, biome: String, min_level: int = 1) -> Dictionary:
	return {"schema_version":VERSION,"settlement_id":id,"biome_id":biome,"min_level":min_level}

static func instance(instance_id: String, settlement_id: String, biome_id: String, seed_value: int, generation_version: int, width: int, height: int, min_level: int, authority: String = AUTHORITY_LOCAL) -> Dictionary:
	return {
		"schema_version":VERSION,
		"instance_id":instance_id,
		"settlement_id":settlement_id,
		"biome_id":biome_id,
		"seed":seed_value,
		"generation_version":generation_version,
		"width":width,
		"height":height,
		"min_level":min_level,
		"access_policy":POLICY_OPEN_PVP if min_level >= 75 else POLICY_SAFE,
		"authority":authority,
		"lifecycle":STATE_ACTIVE,
		"connections":[],
		"created_at_unix":0
	}

static func validate_settlement(data: Dictionary) -> String:
	if int(data.get("schema_version",-1)) != VERSION:
		return "settlement_schema"
	if String(data.get("settlement_id","")).is_empty() or String(data.get("biome_id","")).is_empty():
		return "settlement_identity"
	if int(data.get("min_level",0)) < 1:
		return "settlement_level"
	return ""

static func validate_instance(data: Dictionary, settlements: Dictionary) -> String:
	if int(data.get("schema_version",-1)) != VERSION:
		return "map_schema"
	var id := String(data.get("instance_id",""))
	var town_id := String(data.get("settlement_id",""))
	if id.is_empty() or town_id.is_empty() or String(data.get("biome_id","")).is_empty():
		return "map_identity"
	if not settlements.has(town_id) or not settlements[town_id] is Dictionary:
		return "map_unknown_settlement"
	var town: Dictionary = settlements[town_id]
	var town_error := validate_settlement(town)
	if not town_error.is_empty():
		return town_error
	if town_id != String(town.get("settlement_id","")) or String(data["biome_id"]) != String(town["biome_id"]):
		return "map_settlement_biome_mismatch"
	if int(data.get("generation_version",0)) < 1 or int(data.get("width",0)) < 5 or int(data.get("height",0)) < 5:
		return "map_generation_invalid"
	var level := int(data.get("min_level",0))
	if level < int(town.get("min_level",1)):
		return "map_level_below_settlement"
	if String(data.get("access_policy","")) != (POLICY_OPEN_PVP if level >= 75 else POLICY_SAFE):
		return "map_pvp_policy_mismatch"
	if String(data.get("authority","")) not in [AUTHORITY_LOCAL,AUTHORITY_SERVER]:
		return "map_authority_invalid"
	if String(data.get("lifecycle","")) not in [STATE_ACTIVE,STATE_IDLE,STATE_CLOSED]:
		return "map_lifecycle_invalid"
	var connections: Variant = data.get("connections",null)
	if not connections is Array:
		return "map_connections_invalid"
	var seen: Dictionary = {}
	for connection in connections:
		if not connection is Dictionary:
			return "map_connection_invalid"
		var destination := String(connection.get("destination_id",""))
		if destination.is_empty() or destination == id or seen.has(destination):
			return "map_connection_target_invalid"
		if int(connection.get("travel_seconds",0)) < 1:
			return "map_connection_time_invalid"
		seen[destination] = true
	return ""

## Connections never silently create another map or change biome/settlement.
## The registry is a lookup of identity/metadata, not a second GameState.
static func validate_connection(source: Dictionary, destination: Dictionary, settlements: Dictionary) -> String:
	var issue := validate_instance(source,settlements)
	if not issue.is_empty():
		return issue
	issue = validate_instance(destination,settlements)
	if not issue.is_empty():
		return issue
	if String(source["settlement_id"]) != String(destination["settlement_id"]) or String(source["biome_id"]) != String(destination["biome_id"]):
		return "map_connection_cross_area"
	if String(destination["lifecycle"]) == STATE_CLOSED:
		return "map_destination_closed"
	var edges: Array = source["connections"]
	for entry in edges:
		if String(entry.get("destination_id","")) == String(destination["instance_id"]):
			return ""
	return "map_connection_not_registered"

static func can_enter(data: Dictionary, settlements: Dictionary, current_settlement_id: String, player_level: int) -> String:
	var issue := validate_instance(data,settlements)
	if not issue.is_empty():
		return issue
	if String(data["lifecycle"]) == STATE_CLOSED:
		return "map_closed"
	if String(data["settlement_id"]) != current_settlement_id:
		return "map_wrong_settlement"
	if player_level < int(data["min_level"]):
		return "map_level_locked"
	return ""

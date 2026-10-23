class_name WorldInstanceLifecyclePolicy
extends RefCounted

## Solo and future authoritative MP maps are disposable worlds.
## A map is never archived when closed; character/item ownership lives elsewhere.
const HOUR_SECONDS := 3600

## Solo remains active, including while the character is back in town.
## Starting another expedition closes the old map immediately.
static func solo_after_new_expedition(_now_unix: int) -> Dictionary:
	return {"lifecycle":"closed","discard_world":true}

## MP: last participant leaves -> idle; another participant returns before
## the timeout -> active; one hour continuously empty -> closed/discarded.
## Server presence/transaction validation is not implemented here.
static func multiplayer_next(lifecycle: String, online_count: int, empty_since_unix: int, _archived_at_unix: int, now_unix: int) -> Dictionary:
	if online_count < 0 or now_unix < 0:
		return {"ok":false,"reason":"invalid_lifecycle_input"}
	if lifecycle == "closed":
		return {"ok":true,"lifecycle":"closed","empty_since_unix":empty_since_unix,"discard_world":true}
	if lifecycle not in ["active","idle"]:
		return {"ok":false,"reason":"unknown_lifecycle"}
	if online_count > 0:
		return {"ok":true,"lifecycle":"active","empty_since_unix":-1,"discard_world":false}
	if lifecycle == "active":
		return {"ok":true,"lifecycle":"idle","empty_since_unix":now_unix,"discard_world":false}
	if empty_since_unix < 0 or empty_since_unix > now_unix:
		return {"ok":false,"reason":"invalid_idle_started_at"}
	if now_unix-empty_since_unix >= HOUR_SECONDS:
		return {"ok":true,"lifecycle":"closed","empty_since_unix":empty_since_unix,"discard_world":true}
	return {"ok":true,"lifecycle":"idle","empty_since_unix":empty_since_unix,"discard_world":false}

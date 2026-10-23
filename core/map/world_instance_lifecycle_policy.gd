class_name WorldInstanceLifecyclePolicy
extends RefCounted

## Pure decisions shared by Solo and the future server-owned MP lifecycle.
## No server presence tracking, storage writes or background timers here.
const HOUR_SECONDS := 3600
const MODE_SOLO := "solo"
const MODE_MULTIPLAYER := "multiplayer"

## Solo: an active map has no inactivity timeout. Its archive timer begins
## only after the player explicitly starts a *different* expedition.
static func solo_after_new_expedition(now_unix: int) -> Dictionary:
	return {"lifecycle":"archived","archived_at_unix":now_unix,"expires_at_unix":now_unix+HOUR_SECONDS}

## MP proposal: idle starts when the LAST online participant leaves.
## Online participants reset any idle countdown. After an hour empty, the
## map is archived for another hour and then can be retired.
## Server is responsible for authoritative participant counts and commits.
static func multiplayer_next(lifecycle: String, online_count: int, empty_since_unix: int, archived_at_unix: int, now_unix: int) -> Dictionary:
	if online_count < 0 or now_unix < 0:
		return {"ok":false,"reason":"invalid_lifecycle_input"}
	if lifecycle == "closed":
		return {"ok":true,"lifecycle":"closed","empty_since_unix":empty_since_unix,"archived_at_unix":archived_at_unix}
	if online_count > 0:
		if lifecycle == "archived":
			# Reopening an archived map is a separate explicit server policy.
			return {"ok":true,"lifecycle":"archived","empty_since_unix":-1,"archived_at_unix":archived_at_unix,"requires_restore":true}
		return {"ok":true,"lifecycle":"active","empty_since_unix":-1,"archived_at_unix":-1}
	if lifecycle == "active":
		return {"ok":true,"lifecycle":"idle","empty_since_unix":now_unix,"archived_at_unix":-1}
	if lifecycle == "idle":
		if empty_since_unix < 0 or empty_since_unix > now_unix:
			return {"ok":false,"reason":"invalid_idle_started_at"}
		if now_unix-empty_since_unix < HOUR_SECONDS:
			return {"ok":true,"lifecycle":"idle","empty_since_unix":empty_since_unix,"archived_at_unix":-1}
		return {"ok":true,"lifecycle":"archived","empty_since_unix":empty_since_unix,"archived_at_unix":empty_since_unix+HOUR_SECONDS}
	if lifecycle == "archived":
		if archived_at_unix < 0 or archived_at_unix > now_unix:
			return {"ok":false,"reason":"invalid_archived_at"}
		if now_unix-archived_at_unix >= HOUR_SECONDS:
			return {"ok":true,"lifecycle":"closed","empty_since_unix":empty_since_unix,"archived_at_unix":archived_at_unix}
		return {"ok":true,"lifecycle":"archived","empty_since_unix":empty_since_unix,"archived_at_unix":archived_at_unix}
	return {"ok":false,"reason":"unknown_lifecycle"}

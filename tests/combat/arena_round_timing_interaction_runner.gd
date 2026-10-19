extends SceneTree

## Real ArenaCombatSession, rather than a separate mock engine: verify that
## instant ABI from either actor precedes STANDARD ABI and weapon damage in
## the SAME round, including early dispel against a standard re-buff.
const EFF_GUARD := "EFF_ARENA_TIMING_GUARD"
const EARLY_GUARD := "ABI_TEST_INSTANT_GUARD"
const STANDARD_HIT := "ABI_TEST_STANDARD_HIT"
const EARLY_DISPEL := "ABI_TEST_INSTANT_DISPEL"
const STANDARD_GUARD := "ABI_TEST_STANDARD_GUARD"

func _init() -> void:
	if not _test_player_instant_npc_standard():
		_finish(false, "player_instant_npc_standard")
		return
	if not _test_npc_instant_player_standard():
		_finish(false, "npc_instant_player_standard")
		return
	if not _test_instant_dispel_before_standard_buff():
		_finish(false, "instant_dispel_before_standard_buff")
		return
	_finish(true, "same_round_instant_standard_on_both_actors")

func _session() -> ArenaCombatSession:
	var items := ItemRepository.new()
	var hero := CharacterState.new("TIMING_HERO","Timing Hero",5)
	var session := ArenaCombatSession.new(hero,items)
	var hero_state := session.fighter(true)
	var npc_state := session.fighter(false)
	hero_state.max_hp = 1000
	hero_state.hp = 1000
	npc_state.max_hp = 10000
	npc_state.hp = 10000
	hero_state.max_mana = 100
	hero_state.mana = 100
	npc_state.max_mana = 100
	npc_state.mana = 100
	session.engine.physical_balance["effects"] = {
		EFF_GUARD: {
			"kind": "buff",
			"name": "Round Guard",
			"damage_reduction": 0.5,
			"duration_rounds": 2
		}
	}
	return session

func _configure(session: ArenaCombatSession, player_abi: String, npc_abi: String, definitions: Dictionary) -> void:
	session.ability_scheduler.definitions = definitions
	session.ability_scheduler.loadouts[session.player_id] = [player_abi]
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = [npc_abi]
	session.player_ability_slots[0] = player_abi

func _guard(timing: String) -> Dictionary:
	return {
		"application_timing": timing,
		"target_team": "ALLY",
		"delivery_type": "DIRECT",
		"components": [{"kind": "effect", "effect_id": EFF_GUARD, "base_chance": 100}],
		"mana_cost": 5
	}

func _hit() -> Dictionary:
	return {
		"application_timing": "standard",
		"delivery_type": "DIRECT",
		"components": [{"kind": "damage", "amount": 30.0, "damage_type": "physical"}],
		"mana_cost": 5
	}

func _block_zones(session: ArenaCombatSession) -> Array[String]:
	var zones: Array[String] = []
	var available: Array[String] = ["head","chest","arms","waist"]
	var count: int = CombatModifierService.manual_block_zone_capacity(session.fighter(true))
	for index in range(mini(count, available.size())):
		zones.append(available[index])
	return zones

func _run(session: ArenaCombatSession, selected: String) -> bool:
	var result: Dictionary = session.play_round(["chest"], _block_zones(session), selected)
	if not bool(result.get("ok",false)):
		print("ARENA_TIMING_ROUND_REJECTED=",result)
		return false
	return session.state.round_number == 1

func _casts_in_first_round(session: ArenaCombatSession, player_abi: String, npc_abi: String) -> bool:
	var player_count := 0
	var npc_count := 0
	for event in session.state.event_log:
		if event.kind != CombatEvent.Kind.ACTION:
			continue
		if int(event.payload.get("round",-1)) != 1:
			return false
		if event.source_id == session.player_id and String(event.payload.get("ability_id","")) == player_abi:
			player_count += 1
		if event.source_id == ArenaCombatSession.ENEMY_ID and String(event.payload.get("ability_id","")) == npc_abi:
			npc_count += 1
	return player_count == 1 and npc_count == 1

func _ability_damage_reduction(session: ArenaCombatSession, caster_id: String) -> float:
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and event.source_id == caster_id and String(event.payload.get("source","")) == "ability":
			return float(event.result.get("damage_reduction",-1.0))
	return -1.0

func _test_player_instant_npc_standard() -> bool:
	var session := _session()
	_configure(session,EARLY_GUARD,STANDARD_HIT,{EARLY_GUARD:_guard("instant"),STANDARD_HIT:_hit()})
	var options := session.player_ability_options()
	if not bool(options[0].get("available",false)):
		return false
	if not _run(session,EARLY_GUARD):
		return false
	var reduction := _ability_damage_reduction(session,ArenaCombatSession.ENEMY_ID)
	if reduction < 0.49 or reduction > 0.51:
		print("ARENA_TIMING_PLAYER_GUARD_REDUCTION=",reduction)
		return false
	if not _casts_in_first_round(session,EARLY_GUARD,STANDARD_HIT):
		return false
	return session.fighter(true).mana == 95 and session.fighter(false).mana == 95

func _test_npc_instant_player_standard() -> bool:
	var session := _session()
	_configure(session,STANDARD_HIT,EARLY_GUARD,{STANDARD_HIT:_hit(),EARLY_GUARD:_guard("instant")})
	if not _run(session,STANDARD_HIT):
		return false
	var reduction := _ability_damage_reduction(session,session.player_id)
	if reduction < 0.49 or reduction > 0.51:
		print("ARENA_TIMING_NPC_GUARD_REDUCTION=",reduction)
		return false
	if not _casts_in_first_round(session,STANDARD_HIT,EARLY_GUARD):
		return false
	return session.fighter(true).mana == 95 and session.fighter(false).mana == 95

func _test_instant_dispel_before_standard_buff() -> bool:
	var session := _session()
	var purge := {
		"application_timing": "instant",
		"combat_role": "CLEANSE",
		"target_team": "ENEMY",
		"components": [{"kind":"cleanse","dispel_polarity":"BUFF","max_effects":1}],
		"mana_cost": 5
	}
	_configure(session,EARLY_DISPEL,STANDARD_GUARD,{EARLY_DISPEL:purge, STANDARD_GUARD:_guard("standard")})
	var npc := session.fighter(false)
	var old_effect := {
		"effect_id": EFF_GUARD,
		"definition": {"kind":"buff","damage_reduction":0.5,"duration_rounds":2},
		"source_id": ArenaCombatSession.ENEMY_ID,
		"start_round": 1,
		"remaining_rounds": 2,
		"stacks": 1
	}
	npc.active_effects.append(old_effect)
	if not _run(session,EARLY_DISPEL):
		return false
	if not _casts_in_first_round(session,EARLY_DISPEL,STANDARD_GUARD):
		return false
	var dispel_count := 0
	var dispel_id := -1
	var reapply_id := -1
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("dispel_polarity","")) == "BUFF":
			dispel_count += int(event.result.get("removed_count",0))
			dispel_id = event.event_id
		if event.kind == CombatEvent.Kind.EFFECT and String(event.payload.get("effect_id","")) == EFF_GUARD and event.source_id == ArenaCombatSession.ENEMY_ID:
			reapply_id = event.event_id
	if dispel_count != 1 or dispel_id < 0 or reapply_id <= dispel_id:
		print("ARENA_TIMING_DISPEL_ORDER=",dispel_count," ",dispel_id," ",reapply_id)
		return false
	if npc.active_effects.size() != 1:
		return false
	var restored: Dictionary = npc.active_effects[0]
	# Standard ABI at round 1 writes its new EFF for round 2, but its
	# casting ACTION was completed in round 1. No ABI itself is delayed.
	return String(restored.get("effect_id","")) == EFF_GUARD and int(restored.get("start_round",-1)) == 2

func _finish(ok: bool, detail: String) -> void:
	print("ARENA_ROUND_TIMING_INTERACTION_TEST=", "PASS" if ok else "FAIL", " detail=", detail)
	quit(0 if ok else 1)

class_name ArenaCombatSession
extends RefCounted

var state: CombatState
var engine: CombatEngine
var orchestrator: RoundOrchestrator
var commands: CombatCommandApi
var player_id: String
const ENEMY_ID := "arena_training_enemy"

func _init(character: CharacterState, repository: ItemRepository) -> void:
	state = CombatState.new()
	var player := CharacterCombatBuilder.build(character, repository)
	player_id = player.combatant_id
	var enemy := CombatantState.new(ENEMY_ID, "Тренировочный противник", player.level, 100, 0)
	enemy.combat_stats["weapon_profiles"] = [{"damage_min": 3.0, "damage_max": 6.0, "damage_type": "blunt"}]
	state.add_combatant(player)
	state.add_combatant(enemy)
	var group := GroupCombatState.new(state)
	group.add_member("player", player_id)
	group.add_member("enemy", ENEMY_ID)
	var zones := CombatZoneState.new(group)
	zones.set_team_flag("player", CombatZoneState.ZONE_1)
	zones.set_team_flag("enemy", CombatZoneState.ZONE_3)
	zones.set_zone(player_id, CombatZoneState.ZONE_2)
	zones.set_zone(ENEMY_ID, CombatZoneState.ZONE_2)
	group.set_active_opponent(player_id, ENEMY_ID)
	group.set_active_opponent(ENEMY_ID, player_id)
	engine = CombatEngine.new(state)
	orchestrator = RoundOrchestrator.new(state, engine, group, zones)
	commands = CombatCommandApi.new(state, group, zones, orchestrator)

func fighter(is_player: bool) -> CombatantState:
	return state.get_combatant(player_id if is_player else ENEMY_ID)

func player_attack_count() -> int:
	var sequence: Dictionary = commands.default_weapon_attack_sequence(player_id)
	var count := 0
	for raw_attack in Array(sequence.get("attacks", [])):
		var attack: Dictionary = raw_attack
		for profile in WeaponAttackProfile.all(fighter(true)):
			if int(profile.get("weapon_index", -1)) == int(attack.get("weapon_index", -2)) and String(profile.get("id", "")) == String(attack.get("attack_profile_id", "")):
				count += int(profile.get("hit_count", 1))
				break
	return maxi(1, count)

func _queue_attacks(id: String, targets: Array[String]) -> Dictionary:
	var sequence: Dictionary = commands.default_weapon_attack_sequence(id)
	if not bool(sequence.get("ok", false)):
		return sequence
	var attacks: Array[Dictionary] = []
	var offset := 0
	for raw_attack in Array(sequence.get("attacks", [])):
		var attack: Dictionary = raw_attack.duplicate(true)
		var count := 1
		for profile in WeaponAttackProfile.all(state.get_combatant(id)):
			if int(profile.get("weapon_index", -1)) == int(attack.get("weapon_index", -2)) and String(profile.get("id", "")) == String(attack.get("attack_profile_id", "")):
				count = int(profile.get("hit_count", 1))
				break
		var hits: Array[Dictionary] = []
		for i in range(count):
			var zone := targets[mini(offset + i, targets.size() - 1)] if not targets.is_empty() else "chest"
			hits.append({"zone": zone, "hit": randi_range(1, 100), "reaction": randi_range(1, 100), "dodge": randi_range(1, 100), "crit": randi_range(1, 100), "auto_block": randi_range(1, 100), "block_crush": randi_range(1, 100), "damage": randf()})
		offset += count
		attack["rolls"] = {"zone": String(hits[0].get("zone", "chest")), "hits": hits}
		attacks.append(attack)
	return commands.queue_weapon_attack_sequence(id, attacks)

func play_round(attacks: Array[String], blocks: Array[String]) -> Dictionary:
	if orchestrator.battle_outcome() != "ongoing":
		return {"ok": false, "reason": "battle_finished"}
	var round := orchestrator.begin_round()
	var block_result := commands.set_manual_block(player_id, blocks)
	if not bool(block_result.get("ok", false)):
		return {"ok": false, "reason": String(block_result.get("reason", "invalid_block"))}
	var player_result := _queue_attacks(player_id, attacks)
	if not bool(player_result.get("ok", false)):
		return {"ok": false, "reason": String(player_result.get("reason", "attack_rejected"))}
	var enemy_result := _queue_attacks(ENEMY_ID, ["chest"])
	if not bool(enemy_result.get("ok", false)):
		return {"ok": false, "reason": String(enemy_result.get("reason", "enemy_attack_rejected"))}
	orchestrator.resolve_locked_actions(round)
	var outcome: Dictionary = orchestrator.end_round()
	var lines: Array[String] = []
	for event in state.event_log:
		if int(event.payload.get("round", -1)) != state.round_number or event.kind != CombatEvent.Kind.ATTACK:
			continue
		var actor := "Игрок" if event.source_id == player_id else "Противник"
		lines.append("%s → %s: %s" % [actor, String(event.payload.get("zone", "chest")), String(event.result.get("outcome", ""))])
	return {"ok": true, "round": state.round_number, "lines": lines, "outcome": String(outcome.get("battle_outcome", "ongoing"))}

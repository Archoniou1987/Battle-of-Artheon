class_name ArenaCombatSession
extends RefCounted

var state: CombatState
var engine: CombatEngine
var orchestrator: RoundOrchestrator
var commands: CombatCommandApi
var player_id: String
const ENEMY_ID := "arena_training_enemy"
# Preview-only loadout overrides selected in the inventory generator.
static var training_dummy_items: Dictionary = {}
static var training_dummy_clear_defaults := false
var enemy_equipment_display: Dictionary = {}

func _init(character: CharacterState, repository: ItemRepository) -> void:
	state = CombatState.new()
	var player := CharacterCombatBuilder.build(character, repository)
	player_id = player.combatant_id
	var enemy_character := CharacterState.new(ENEMY_ID, "Тренировочный противник", player.level)
	var enemy_repository := ItemRepository.new()
	var sword := {"instance_id":"arena_enemy_sword", "equip_slots":["main_hand"], "slot_usage":["main_hand"], "par_stats":{"PAR057":1}, "damage":{"min":4.0,"max":7.0,"type":"slashing"}}
	ItemDurabilityService.initialize_item(sword, 100)
	enemy_repository.add_item(sword)
	enemy_character.receive_item("arena_enemy_sword", enemy_repository)
	enemy_character.equip("main_hand", "arena_enemy_sword", enemy_repository)
	var default_gear: Array = [] if training_dummy_clear_defaults else [{"template_id":"audit_enemy_shield","instance_id":"arena_enemy_audit_shield","slot":"off_hand"},{"template_id":"audit_enemy_fire_helmet","instance_id":"arena_enemy_audit_helmet","slot":"head"}]
	for gear in default_gear:
		var item: Dictionary = ItemTemplateService.resolve(gear)
		if item.is_empty():
			push_error("Arena enemy test equipment template missing: " + String(gear["template_id"]))
			continue
		ItemDurabilityService.initialize_item(item, 100)
		enemy_repository.add_item(item)
		enemy_character.receive_item(String(gear["instance_id"]), enemy_repository)
		if not enemy_character.equip(String(gear["slot"]), String(gear["instance_id"]), enemy_repository):
			push_error("Arena enemy failed to equip: " + String(gear["template_id"]))
	for slot in training_dummy_items:
		var instance: Dictionary = Dictionary(training_dummy_items[slot]).duplicate(true)
		var item: Dictionary = ItemTemplateService.resolve(instance)
		if item.is_empty():
			push_error("Invalid training dummy item for slot: " + String(slot))
			continue
		var old_id: Variant = enemy_character.equipment.get_equipped_instance_id(String(slot))
		if old_id != null:
			enemy_character.unequip(String(slot), enemy_repository)
		ItemDurabilityService.initialize_item(instance, 100)
		if enemy_repository.add_item(instance) and enemy_character.receive_item(String(instance["instance_id"]), enemy_repository):
			if not enemy_character.equip(String(slot), String(instance["instance_id"]), enemy_repository):
				push_error("Cannot equip training dummy item in: " + String(slot))
	for slot in enemy_character.equipment.slots:
		var equipped_id: Variant = enemy_character.equipment.get_equipped_instance_id(String(slot))
		if equipped_id != null:
			enemy_equipment_display[String(slot)] = ItemTemplateService.resolve(enemy_repository.get_item(String(equipped_id)))
	var enemy := CharacterCombatBuilder.build(enemy_character, enemy_repository, {"health":10000,"mana":0})
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
	if CombatModifierService.effective_tempo(fighter(true), state.round_number) <= -100:
		commands.clear_manual_block(player_id)
	else:
		var block_result := commands.set_manual_block(player_id, blocks)
		if not bool(block_result.get("ok", false)):
			return {"ok": false, "reason": String(block_result.get("reason", "invalid_block"))}
		var player_result := _queue_attacks(player_id, attacks)
		if not bool(player_result.get("ok", false)):
			return {"ok": false, "reason": String(player_result.get("reason", "attack_rejected"))}
	if CombatModifierService.effective_tempo(fighter(false), state.round_number) > -100:
		var enemy_result := _queue_attacks(ENEMY_ID, ["chest"])
		if not bool(enemy_result.get("ok", false)):
			return {"ok": false, "reason": String(enemy_result.get("reason", "enemy_attack_rejected"))}
	orchestrator.resolve_locked_actions(round)
	var outcome: Dictionary = orchestrator.end_round()
	var lines: Array[String] = []
	var damage_by_attack: Dictionary = {}
	for event in state.event_log:
		if int(event.payload.get("round", -1)) != state.round_number:
			continue
		if event.kind == CombatEvent.Kind.DAMAGE and event.parent_event_id >= 0:
			damage_by_attack[event.parent_event_id] = int(event.result.get("hp_removed", 0))
	for event in state.event_log:
		if int(event.payload.get("round", -1)) != state.round_number or event.kind != CombatEvent.Kind.ATTACK:
			continue
		var actor := "Игрок" if event.source_id == player_id else "Противник"
		var defender := "противника" if event.source_id == player_id else "игрока"
		var zone := _zone_name(String(event.payload.get("zone", "chest")))
		var outcome_text := String(event.result.get("outcome", ""))
		match outcome_text:
			"connected":
				var damage := int(damage_by_attack.get(event.event_id, 0))
				var critical := " (критический удар)" if bool(event.result.get("critical", false)) else ""
				lines.append("%s атакует %s (%s): %d урона%s" % [actor, defender, zone, damage, critical])
			"manual_block":
				lines.append("%s атакует %s (%s): удар заблокирован" % [actor, defender, zone])
			"auto_block":
				lines.append("%s атакует %s (%s): удар отражён щитом" % [actor, defender, zone])
			"dodge":
				lines.append("%s атакует %s (%s): уклонение" % [actor, defender, zone])
			"miss", "magic_miss":
				lines.append("%s атакует %s (%s): промах" % [actor, defender, zone])
			_:
				lines.append("%s атакует %s (%s): %s" % [actor, defender, zone, outcome_text])
	return {"ok": true, "round": state.round_number, "lines": lines, "outcome": String(outcome.get("battle_outcome", "ongoing"))}

static func _zone_name(zone: String) -> String:
	match zone:
		"head": return "голова"
		"chest": return "грудь"
		"arms": return "руки"
		"waist": return "пояс"
		"legs": return "ноги"
		_: return zone

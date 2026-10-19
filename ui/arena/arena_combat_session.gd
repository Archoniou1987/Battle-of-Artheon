class_name ArenaCombatSession
extends RefCounted

var state: CombatState
var engine: CombatEngine
var orchestrator: RoundOrchestrator
var commands: CombatCommandApi
var ability_scheduler: AbilityScheduler
## Five equipment ABI positions: three from MH, one from chest, one from head.
var player_ability_slots: Array = []
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
	if not training_dummy_clear_defaults:
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
	var equipment_slots := EquipmentAbilityLoadout.build(character, repository)
	for group_name in ["weapon", "chest", "head"]:
		player_ability_slots.append_array(Array(equipment_slots.get(group_name, [])))
	# Only the canonical live ABI catalog is executable in Arena. Development
	# fixture IDs are never silently substituted for production definitions.
	ability_scheduler = AbilityScheduler.new(AbilityCatalog.load_json("res://data/abilities/catalog.json"), {
		player_id: Array(player.combat_stats.get("abilities", [])).duplicate(),
		ENEMY_ID: Array(enemy.combat_stats.get("abilities", [])).duplicate()
	})
	commands = CombatCommandApi.new(state, group, zones, orchestrator, ability_scheduler)

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

func player_ability_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ready_round := state.round_number + 1
	var player := fighter(true)
	var cooldowns: Dictionary = ability_scheduler.cooldowns_by_combatant.get(player_id, {})
	for raw_id in player_ability_slots:
		var ability_id := "" if raw_id == null else String(raw_id)
		var definition := AbilityCatalog.definition(ability_scheduler.definitions, ability_id)
		var available := not definition.is_empty() and player != null and player.hp > 0 and not player.is_death_finalized()
		available = available and not CombatTempoService.is_stunned(player,ready_round)
		available = available and ability_scheduler.can_cast_this_round(player_id,ready_round)
		available = available and AbilityRuntime.can_use(ability_id,cooldowns,ready_round)
		available = available and player.mana >= int(definition.get("mana_cost",0))
		result.append({"id":ability_id,"name":String(definition.get("name",ability_id)),"available":available,"mana_cost":int(definition.get("mana_cost",0)),"cooldown_until":int(cooldowns.get(ability_id,0)),"defined":not definition.is_empty()})
	return result

func _prepare_attacks(id: String, targets: Array[String]) -> Dictionary:
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
			hits.append({"zone": zone})
		offset += count
		attack["rolls"] = {"zone": String(hits[0].get("zone", "chest")), "hits": hits}
		attacks.append(attack)
	return {"ok":true,"attacks":attacks}

func _queue_attacks(id: String, targets: Array[String]) -> Dictionary:
	var plan := _prepare_attacks(id,targets)
	if not bool(plan.get("ok",false)):
		return plan
	return commands.queue_weapon_attack_sequence(id,Array(plan.get("attacks",[])))

func _ability_target(source_id:String,definition:Dictionary) -> String:
	return source_id if String(definition.get("target_team", "")).to_upper()=="ALLY" else (ENEMY_ID if source_id==player_id else player_id)

func _validate_ability(source_id:String,ability_id:String,ready_round:int) -> Dictionary:
	if ability_id.is_empty():
		return {"ok":true}
	var definition := AbilityCatalog.definition(ability_scheduler.definitions,ability_id)
	if definition.is_empty() or not AbilityCatalog.assigned_abilities(ability_scheduler.loadouts,source_id).has(ability_id):
		return {"ok":false,"reason":"ability_unavailable"}
	var actor := state.get_combatant(source_id)
	if actor==null or actor.is_death_finalized() or CombatTempoService.is_stunned(actor,ready_round):
		return {"ok":false,"reason":"ability_actor_unavailable"}
	if not AbilityRuntime.validate_definition(ability_id,definition).is_empty():
		return {"ok":false,"reason":"invalid_ability_definition"}
	if not ability_scheduler.can_cast_this_round(source_id,ready_round):
		return {"ok":false,"reason":"abi_limit_reached"}
	if not AbilityRuntime.can_use(ability_id,ability_scheduler.cooldowns_by_combatant.get(source_id,{}),ready_round):
		return {"ok":false,"reason":"ability_cooldown"}
	if actor.mana < int(definition.get("mana_cost",0)):
		return {"ok":false,"reason":"insufficient_mana"}
	var target_id:=_ability_target(source_id,definition)
	if not commands.action_policy.valid_ability_targets(source_id,definition).has(target_id):
		return {"ok":false,"reason":"ability_target_unavailable"}
	return {"ok":true,"target_id":target_id}

func play_round(attacks: Array[String], blocks: Array[String], ability_id: String = "") -> Dictionary:
	# A persistent character at 0 HP cannot start acting again merely by
	# reopening a test duel. A new life/recovery rule must be explicit.
	if fighter(true).hp <= 0:
		return {"ok": false, "reason": "player_has_no_hp"}
	if orchestrator.battle_outcome() != "ongoing":
		return {"ok": false, "reason": "battle_finished"}
	var round := orchestrator.begin_round()
	if CombatTempoService.is_stunned(fighter(true), state.round_number):
		commands.clear_manual_block(player_id)
	else:
		var block_result := commands.set_manual_block(player_id, blocks)
		if not bool(block_result.get("ok", false)):
			return {"ok": false, "reason": String(block_result.get("reason", "invalid_block"))}
		var player_result := _queue_attacks(player_id, attacks)
		if not bool(player_result.get("ok", false)):
			return {"ok": false, "reason": String(player_result.get("reason", "attack_rejected"))}
	if not CombatTempoService.is_stunned(fighter(false), state.round_number):
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

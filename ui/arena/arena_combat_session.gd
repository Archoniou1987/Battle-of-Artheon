class_name ArenaCombatSession
extends RefCounted

var state: CombatState
var engine: CombatEngine
var orchestrator: RoundOrchestrator
var commands: CombatCommandApi
var elixir_service: CombatElixirService
var active_round: CombatRound
var locked_ability_id := ""
var character: CharacterState
var repository: ItemRepository
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
	self.character = character
	self.repository = repository
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
	var combat_ability_loadouts: Dictionary = {}
	combat_ability_loadouts[player_id] = Array(player.combat_stats.get("abilities", [])).duplicate()
	combat_ability_loadouts[ENEMY_ID] = Array(enemy.combat_stats.get("abilities", [])).duplicate()
	ability_scheduler = AbilityScheduler.new(AbilityCatalog.load_json("res://data/abilities/catalog.json"), combat_ability_loadouts)
	commands = CombatCommandApi.new(state, group, zones, orchestrator, ability_scheduler)
	elixir_service = CombatElixirService.new(state, engine)

func fighter(is_player: bool) -> CombatantState:
	return state.get_combatant(player_id if is_player else ENEMY_ID)

## View-only EFF snapshot. Newly applied instant ABI EFF stay hidden
## until end_round reveals them; this does NOT change active modifiers.
## Standard pending EFF keep their existing pending visual treatment.
func effect_view(is_player: bool) -> Dictionary:
	var beneficial: Array[Dictionary] = []
	var harmful: Array[Dictionary] = []
	var combatant := fighter(is_player)
	if combatant == null:
		return {"buffs":beneficial,"debuffs":harmful}
	for record in combatant.active_effects:
		if not record is Dictionary or int(record.get("remaining_rounds",0))<=0:
			continue
		# Surprise effects apply mechanically, but do not leak through the
		# opponent (or owner) effect panel before end_round.
		if not bool(record.get("revealed",true)):
			continue
		var definition:Dictionary=Dictionary(record.get("definition",{}))
		var polarity:=EffectPolarity.of(definition)
		if polarity.is_empty():
			continue
		var effect_id:=String(record.get("effect_id",""))
		var effect_name:=String(definition.get("name",effect_id))
		var kind:=String(definition.get("kind","")).to_lower()
		# Preserve the last disclosed shared-EFF stack count/duration
		# until this round ends. The hidden increment already acts internally.
		var stacks:=maxi(1,int(record.get("stacks",1))-maxi(0,int(record.get("undisclosed_stacks",0))))
		var remaining:=int(record.get("visible_remaining_rounds",record.get("remaining_rounds",0)))
		var pending:=int(record.get("start_round",state.round_number))>state.round_number
		var entry:Dictionary={
			"id":effect_id,
			"name":effect_name,
			"kind":kind,
			"stacks":stacks,
			"remaining_rounds":remaining,
			"pending":pending,
			"source_id":String(record.get("source_id",""))
		}
		if polarity=="BUFF":
			beneficial.append(entry)
		else:
			harmful.append(entry)
	return {"buffs":beneficial,"debuffs":harmful}

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
	var ready_round := state.round_number if active_round != null else state.round_number + 1
	var player := fighter(true)
	var cooldowns: Dictionary = ability_scheduler.cooldowns_by_combatant.get(player_id, {})
	for raw_id in player_ability_slots:
		var ability_id := "" if raw_id == null else String(raw_id)
		var definition := AbilityCatalog.definition(ability_scheduler.definitions, ability_id)
		var available := not definition.is_empty() and player != null and player.hp > 0 and not player.is_death_finalized() and orchestrator.battle_outcome()=="ongoing"
		available = available and not CombatTempoService.is_stunned(player,ready_round)
		available = available and ability_scheduler.can_cast_this_round(player_id,ready_round)
		available = available and AbilityRuntime.can_use(ability_id,cooldowns,ready_round)
		available = available and player.mana >= int(definition.get("mana_cost",0))
		available = available and AbilityRuntime.validate_definition(ability_id,definition).is_empty()
		var target_id:=_ability_target(player_id,definition)
		available = available and commands.action_policy.valid_ability_targets(player_id,definition).has(target_id)
		var target_label:="Себя" if String(definition.get("target_team","")).to_upper()=="ALLY" else "Противник"
		result.append({"id":ability_id,"name":String(definition.get("name",ability_id)),"available":available,"mana_cost":int(definition.get("mana_cost",0)),"cooldown_until":int(cooldowns.get(ability_id,0)),"defined":not definition.is_empty(),"target_id":target_id,"target_label":target_label})
	return result

## Current Mind Game round opens on the first instant action, not on End Turn.
func _ensure_round() -> void:
	if active_round == null:
		active_round = orchestrator.begin_round()

func activate_ability(ability_id: String) -> Dictionary:
	if active_round != null and not locked_ability_id.is_empty():
		return {"ok":false, "reason":"abi_limit_reached"}
	var target_round := state.round_number if active_round != null else state.round_number + 1
	var check := _validate_ability(player_id,ability_id,target_round)
	if not bool(check.get("ok",false)) or ability_id.is_empty():
		return {"ok":false,"reason":String(check.get("reason","ability_unavailable"))}
	_ensure_round()
	var target_id: String = String(check.get("target_id",""))
	var result := commands.cast_ability(player_id,target_id,ability_id)
	if not bool(result.get("ok",false)):
		return result
	locked_ability_id=ability_id
	# Detach the committed root before resolving: instant ABI children may
	# enqueue EFF and must never be accidentally reclassified as Standard.
	var roots: Array[CombatEvent] = state.pending_events.duplicate()
	state.pending_events.clear()
	for event in roots:
		if String(event.payload.get("application_timing","standard"))=="instant":
			engine.resolve_event(event)
		else:
			active_round.lock_action(event)
	# Instant ACTION children now resolve immediately, exactly once.
	engine.resolve_pending_events()
	return {"ok":true,"timing":AbilityRuntime.application_timing(AbilityCatalog.definition(ability_scheduler.definitions,ability_id))}

func elixir_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var capacity := character.elixir_capacity(repository)
	var target_round := state.round_number if active_round != null else state.round_number + 1
	var ready := elixir_service.can_use(fighter(true),target_round) and orchestrator.battle_outcome()=="ongoing"
	for index in range(4):
		var entry: Dictionary = {}
		if index < capacity:
			var item_id: String = character.elixir_slots[index]
			if not item_id.is_empty() and character.inventory.owns(item_id):
				entry = repository.get_item(item_id)
				entry["available"] = ready and int(entry.get("charges",0))>0 and CombatElixirService.validate_components(entry).is_empty()
		out.append(entry)
	return out

func elixir_cooldown() -> int:
	var target_round := state.round_number if active_round != null else state.round_number + 1
	return elixir_service.remaining_cooldown(player_id,target_round)

func use_elixir(index: int) -> Dictionary:
	if orchestrator.battle_outcome()!="ongoing" or fighter(true).hp<=0:
		return {"ok":false,"reason":"battle_finished"}
	if index<0 or index>=character.elixir_capacity(repository):
		return {"ok":false,"reason":"belt_slot_unavailable"}
	var id: String = character.elixir_slots[index]
	if id.is_empty() or not character.inventory.owns(id):
		return {"ok":false,"reason":"elixir_not_owned"}
	var target_round := state.round_number if active_round != null else state.round_number+1
	if not elixir_service.can_use(fighter(true),target_round):
		return {"ok":false,"reason":"elixir_unavailable"}
	var item: Dictionary = repository.get_item(id)
	if CombatElixirService.validate_components(item)!="":
		return {"ok":false,"reason":"invalid_elixir"}
	if int(item.get("charges",0))<=0 or int(item.get("charges",0))>maxi(1,int(item.get("max_charges",1))):
		return {"ok":false,"reason":"invalid_charges"}
	_ensure_round()
	return elixir_service.use(player_id,id,repository)

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
	# Preflight the complete submission before begin_round changes resources,
	# Tempo or the round number. Failed ABI/block/attack does not consume a turn.
	var next_round := state.round_number if active_round != null else state.round_number + 1
	var player_stunned := CombatTempoService.is_stunned(fighter(true),next_round)
	var enemy_stunned := CombatTempoService.is_stunned(fighter(false),next_round)
	if not player_stunned:
		var expected_blocks:=CombatModifierService.manual_block_zone_capacity(fighter(true))
		var unique_blocks:Array[String]=[]
		for body_zone in blocks:
			if not CombatCommandApi.BODY_ZONES.has(body_zone) or unique_blocks.has(body_zone):
				return {"ok":false,"reason":"invalid_block_zone"}
			unique_blocks.append(body_zone)
		if expected_blocks<1 or expected_blocks>4 or unique_blocks.size()!=expected_blocks:
			return {"ok":false,"reason":"invalid_block_zone_count"}
		var player_plan:=_prepare_attacks(player_id,attacks)
		if not bool(player_plan.get("ok",false)):
			return {"ok":false,"reason":String(player_plan.get("reason","attack_rejected"))}
		for requested_zone in attacks:
			if not CombatCommandApi.BODY_ZONES.has(requested_zone):
				return {"ok":false,"reason":"invalid_attack_zone"}
		if not locked_ability_id.is_empty() and not ability_id.is_empty():
			return {"ok":false,"reason":"abi_limit_reached"}
		var player_abi_check:=_validate_ability(player_id,ability_id,next_round)
		if not bool(player_abi_check.get("ok",false)):
			return player_abi_check
	if not enemy_stunned:
		var enemy_plan:=_prepare_attacks(ENEMY_ID,["chest"])
		if not bool(enemy_plan.get("ok",false)):
			return {"ok":false,"reason":String(enemy_plan.get("reason","enemy_attack_rejected"))}
	# All inputs are snapshotted before any engine event is resolved. No subsequent
	# UI selection can change this round's pending physical/ABI actions.
	var round: CombatRound = active_round if active_round != null else orchestrator.begin_round()
	if player_stunned:
		commands.clear_manual_block(player_id)
	else:
		var block_result := commands.set_manual_block(player_id, blocks.duplicate())
		if not bool(block_result.get("ok",false)):
			return {"ok":false,"reason":String(block_result.get("reason","invalid_block"))}
		var player_result := _queue_attacks(player_id,attacks.duplicate())
		if not bool(player_result.get("ok",false)):
			return {"ok":false,"reason":String(player_result.get("reason","attack_rejected"))}
		if not ability_id.is_empty():
			var definition:=AbilityCatalog.definition(ability_scheduler.definitions,ability_id)
			var target_id:=_ability_target(player_id,definition)
			var ability_result:=commands.cast_ability(player_id,target_id,ability_id)
			if not bool(ability_result.get("ok",false)):
				return {"ok":false,"reason":String(ability_result.get("reason","ability_rejected"))}
	if not enemy_stunned:
		var enemy_result := _queue_attacks(ENEMY_ID, ["chest"])
		if not bool(enemy_result.get("ok", false)):
			return {"ok": false, "reason": String(enemy_result.get("reason", "enemy_attack_rejected"))}
		# NPC uses the same one-ABI limit and canonical equipped loadout.
		for enemy_ability in ability_scheduler.ready_events(state,ENEMY_ID,player_id):
			state.queue_event(enemy_ability)
	# Commands queue immutable events. Transfer them into the shared round;
	# preparation ABI are sorted into the early phase by CombatRound.
	for event in state.pending_events:
		round.lock_action(event)
	state.pending_events.clear()
	orchestrator.resolve_locked_actions(round)
	var outcome: Dictionary = orchestrator.end_round()
	active_round=null
	locked_ability_id=""
	# Log only resolved CombatEvent results, grouping ABI children through
	# parent_event_id. A projectile ABI ATTACK is not an extra weapon action.
	var lines: Array[String] = ArenaCombatLog.lines_for_round(
		state.event_log, state.round_number, player_id, ability_scheduler.definitions
	)
	return {"ok": true, "round": state.round_number, "lines": lines, "outcome": String(outcome.get("battle_outcome", "ongoing"))}

static func _zone_name(zone: String) -> String:
	match zone:
		"head": return "голова"
		"chest": return "грудь"
		"arms": return "руки"
		"waist": return "пояс"
		"legs": return "ноги"
		_: return zone

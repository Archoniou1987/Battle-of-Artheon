extends SceneTree

## Runtime smoke for ALL approved physical ABI, not a catalog-only check.
## Each case uses an equipped production weapon, ArenaCombatSession, the real
## scheduler and CombatEngine; seed only the prerequisites that normally arise
## from earlier successful rounds (dodge/crit, bleed, poison, rage, charges).
## Keep this independent of damage balance numbers.
const RANGES := [[301,308],[401,408],[501,508],[601,606]]
const LINKED_MH := ["ABI301","ABI501","ABI601"]
const NON_ATTACK := ["ABI402","ABI501","ABI504","ABI507","ABI602","ABI603","ABI605"]
const INVALID_OUTCOMES := ["invalid_combatant","invalid_target","friendly_target",
	"out_of_range","sword_mh_required","dagger_mh_required","axe_mh_required",
	"hammer_mh_required","no_available_strikes","no_reachable_target",
	"needs_five_rage","unavailable"]
var failures: Array[String] = []
var checked_count := 0

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("APPROVED_ABI_RUNTIME_CASE=FAIL ",label)

func _initialize() -> void:
	for limits in RANGES:
		for number in range(int(limits[0]),int(limits[1])+1):
			_test_ability("ABI%d" % number)
	_test_axe_preflight("ABI506")
	_test_axe_preflight("ABI507")
	_test_trigger_preflight("ABI403")
	_test_trigger_preflight("ABI502")
	_test_low_ap_preflight("ABI408")
	_test_low_ap_preflight("ABI606")
	print("APPROVED_ABI_RUNTIME_MATRIX_TEST=", "PASS" if failures.is_empty() else "FAIL",
		" checked=",checked_count," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _weapon_class(abi: String) -> String:
	if abi.begins_with("ABI3"): return "sword"
	if abi.begins_with("ABI4"): return "dagger"
	if abi.begins_with("ABI5"): return "axe"
	return "hammer"

func _weapon_damage_type(weapon_class: String) -> String:
	match weapon_class:
		"sword": return "slashing"
		"dagger": return "piercing"
		"axe": return "chopping"
		_: return "blunt"

func _fixture(abi: String) -> ArenaCombatSession:
	var weapon_class := _weapon_class(abi)
	var hero := CharacterState.new("ABI_MATRIX_" + abi, "ABI Matrix", 30)
	var repository := ItemRepository.new()
	var main_hand := {
		"instance_id":"MATRIX_MH_" + abi,
		"equip_slots":["main_hand"], "slot_usage":["main_hand"],
		"weapon_class":weapon_class,
		"abilities":[abi], "par_stats":{"PAR057":1},
		"damage":{"min":20.0,"max":20.0,"type":_weapon_damage_type(weapon_class)}
	}
	ItemDurabilityService.initialize_item(main_hand,100)
	if not repository.add_item(main_hand) or not hero.receive_item(String(main_hand["instance_id"]),repository) or not hero.equip("main_hand",String(main_hand["instance_id"]),repository):
		_check(false,abi + ":main_hand_equipment")
		return null
	# Dagger MH abilities operate with both regular MH and OH hits present.
	if weapon_class == "dagger":
		var off_hand := {
			"instance_id":"MATRIX_OH_" + abi,
			"equip_slots":["off_hand"], "slot_usage":["off_hand"],
			"weapon_class":"dagger", "par_stats":{"PAR057":1},
			"damage":{"min":12.0,"max":12.0,"type":"piercing"}
		}
		ItemDurabilityService.initialize_item(off_hand,100)
		if not repository.add_item(off_hand) or not hero.receive_item(String(off_hand["instance_id"]),repository) or not hero.equip("off_hand",String(off_hand["instance_id"]),repository):
			_check(false,abi + ":off_hand_equipment")
			return null
	var session := ArenaCombatSession.new(hero,repository)
	var player := session.fighter(true)
	var target := session.fighter(false)
	if player == null or target == null:
		_check(false,abi + ":missing_combatants")
		return null
	player.max_hp = 25000
	player.hp = 25000
	target.max_hp = 25000
	target.hp = 25000
	player.max_mana = 500
	player.mana = 500
	player.max_action_points = 8
	# Leave room to observe +AP from zero-cost abilities; expensive casts get 8.
	var definition := AbilityCatalog.definition(session.ability_scheduler.definitions,abi)
	player.action_points = 5 if int(definition.get("ap_cost",0)) == 0 and not bool(definition.get("consume_all_ap",false)) else 8
	player.combat_stats["mana_regen_round"] = 0.0
	target.combat_stats["mana_regen_round"] = 0.0
	player.combat_stats["hit_chance_rating_percent"] = 100.0
	target.combat_stats["dodge_rating_percent"] = 0.0
	target.combat_stats["shield_auto_block_rating_percent"] = 0.0
	target.combat_stats["manual_block_zones"] = []
	target.combat_loadout["can_manual_block"] = false
	target.combat_loadout["can_auto_block"] = false
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = []
	session.engine.combat_rng.seed = 133700 + int(abi.substr(3))
	return session

func _seed_effect(session: ArenaCombatSession, on_player: bool, effect_id: String, stacks: int) -> void:
	var target := session.fighter(on_player)
	var definition: Dictionary = Dictionary(session.engine.canonical_effects.get(effect_id,{})).duplicate(true)
	_check(not definition.is_empty(), effect_id + ":effect_definition")
	target.active_effects.append({
		"effect_id":effect_id, "definition":definition,
		"source_id":session.player_id,
		"start_round":1,"remaining_rounds":99,"stacks":stacks,"revealed":true
	})

func _seed_prerequisites(session: ArenaCombatSession, abi: String) -> void:
	if abi == "ABI403" or abi == "ABI502":
		# Satisfy a TRUE prior-round trigger with the same canonical event
		# fields used by AbilityRuntime.previous_round_trigger_met.
		session.state.round_number = 1
		var attacker_id := ArenaCombatSession.ENEMY_ID if abi == "ABI403" else session.player_id
		var defender_id := session.player_id if abi == "ABI403" else ArenaCombatSession.ENEMY_ID
		var previous := session.state.create_event(CombatEvent.Kind.ATTACK,attacker_id,defender_id,{"is_weapon_attack":true})
		if abi == "ABI403":
			previous.set_result("outcome","dodge")
		else:
			previous.set_result("critical",true)
		session.state.record_event(previous)
	if abi in ["ABI303","ABI304","ABI305","ABI308"]:
		_seed_effect(session,false,"EFF301",4)
	if abi in ["ABI404","ABI406","ABI407","ABI408"]:
		_seed_effect(session,false,"EFF403",6)
		_seed_effect(session,false,"EFF401",3)
	if abi in ["ABI503","ABI504","ABI505","ABI506","ABI507","ABI508"]:
		_seed_effect(session,true,"EFF501",5)
	if abi == "ABI506":
		session.fighter(false).hp = 3000 # Under 20% of 25000 HP.
	if abi in ["ABI603","ABI604","ABI605","ABI606"]:
		_seed_effect(session,true,"EFF601",40)
	if abi == "ABI603":
		session.fighter(true).hp -= 5000

func _blocks(session: ArenaCombatSession) -> Array[String]:
	var result: Array[String] = []
	for zone in ["head","chest","arms","waist"]:
		if result.size() < CombatModifierService.manual_block_zone_capacity(session.fighter(true)):
			result.append(zone)
	return result

func _attacks(session: ArenaCombatSession) -> Array[String]:
	var result: Array[String] = []
	for _index in range(session.player_attack_count()):
		result.append("chest")
	return result

func _test_ability(abi: String) -> void:
	checked_count += 1
	var session := _fixture(abi)
	if session == null:
		return
	_seed_prerequisites(session,abi)
	var definition := AbilityCatalog.definition(session.ability_scheduler.definitions,abi)
	_check(not definition.is_empty(),abi + ":production_definition")
	var slots := session.player_ability_options()
	if slots.is_empty() or String(slots[0].get("id","")) != abi:
		_check(false,abi + ":equipped_abi_slot")
		return
	if not bool(slots[0].get("available",false)):
		_check(false,abi + ":not_available_with_prerequisites")
		return
	var actor := session.fighter(true)
	var initial_ap := actor.action_points
	var initial_mana := actor.mana
	var planned_round := session.state.round_number + 1
	var spent := AbilityRuntime.action_point_cost(definition,actor)
	var immediate_gain := 0 if bool(definition.get("ap_gain_on_hit",false)) else int(definition.get("ap_gain",0))
	var result := session.activate_ability(abi)
	if not bool(result.get("ok",false)):
		_check(false,abi + ":activation_" + String(result.get("reason","unknown")))
		return
	_check(session.state.round_number == planned_round,abi + ":opened_round")
	_check(actor.action_points == mini(actor.max_action_points,initial_ap-spent+immediate_gain),abi + ":ap_cost_and_instant_gain")
	_check(actor.mana == initial_mana-int(definition.get("mana_cost",0)),abi + ":mana_cost")
	var deadline := int(session.ability_scheduler.cooldowns_by_combatant.get(session.player_id,{}).get(abi,-1))
	_check(deadline == planned_round + int(definition.get("cooldown_rounds",0)) + 1,abi + ":cooldown")
	var ap_after := actor.action_points
	_check(not bool(session.activate_ability(abi).get("ok",false)) and actor.action_points == ap_after,abi + ":one_abi_per_round")
	var submission := session.play_round(_attacks(session),_blocks(session))
	if not bool(submission.get("ok",false)):
		_check(false,abi + ":round_" + String(submission.get("reason","unknown")))
		return
	var action_count := 0
	var ordinary_mh := 0
	var ordinary_oh := 0
	var ability_attacks := 0
	var effect_events := 0
	var final_outcome := ""
	var final_action_result: Dictionary = {}
	var abi_attack_ids: Dictionary = {}
	for event in session.state.event_log:
		if event.source_id != session.player_id or int(event.payload.get("round",-1)) != planned_round:
			continue
		if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("ability_id","")) == abi:
			action_count += 1
			final_outcome = String(event.result.get("outcome",""))
			final_action_result = event.result.duplicate(true)
		elif event.kind == CombatEvent.Kind.ATTACK:
			if bool(event.payload.get("is_weapon_attack",false)):
				if int(event.payload.get("weapon_index",-1)) == 0:
					ordinary_mh += 1
					if LINKED_MH.has(abi):
						var key := "sword_abi_id" if abi == "ABI301" else ("axe_abi_id" if abi == "ABI501" else "hammer_abi_id")
						_check(String(event.payload.get(key,"")) == abi,abi + ":linked_mh_identity")
				elif int(event.payload.get("weapon_index",-1)) == 1:
					ordinary_oh += 1
			elif String(event.payload.get("source_kind","")) == "ability":
				ability_attacks += 1
				abi_attack_ids[event.event_id] = true
		elif event.kind == CombatEvent.Kind.EFFECT:
			effect_events += 1
	var abi_damage_events := 0
	for event in session.state.event_log:
		if event.kind == CombatEvent.Kind.DAMAGE and event.source_id == session.player_id and abi_attack_ids.has(event.parent_event_id):
			abi_damage_events += 1
	_check(action_count == 1,abi + ":exactly_one_action")
	_check(not final_outcome.is_empty() and not INVALID_OUTCOMES.has(final_outcome),abi + ":dispatch_" + final_outcome)
	_check(ordinary_mh == 1,abi + ":ordinary_mh_once")
	_check(ordinary_oh == (1 if abi.begins_with("ABI4") else 0),abi + ":ordinary_oh_count")
	if not LINKED_MH.has(abi) and not NON_ATTACK.has(abi):
		_check(ability_attacks > 0,abi + ":ability_attacks_dispatched")
		_check(abi_damage_events > 0,abi + ":damage_event_from_abi_attack")
	if ["ABI404","ABI405","ABI408"].has(abi):
		_check(ability_attacks == 2,abi + ":mh_oh_ability_constituents")
	if abi == "ABI406":
		_check(ability_attacks == 6,abi + ":one_strike_per_consumed_poison")
	if ["ABI301","ABI302","ABI401"].has(abi):
		_check(actor.action_points == mini(actor.max_action_points,ap_after + int(definition.get("ap_gain",0))),abi + ":on_hit_ap_awarded")
	if abi == "ABI407":
		_check(int(final_action_result.get("poison_stacks_consumed",-1)) == 6 and int(final_action_result.get("breach_stacks_to_apply",-1)) == 3,abi + ":poison_to_breach_ratio")
	if abi in ["ABI603","ABI604","ABI605","ABI606"]:
		_check(int(final_action_result.get("charges_consumed",0)) > 0,abi + ":hammer_charges_consumed")
	if abi in ["ABI402","ABI501","ABI504","ABI507","ABI602","ABI603","ABI605"]:
		_check(effect_events > 0,abi + ":effect_event_dispatched")
	var next_options := session.player_ability_options()
	var next_round := session.state.round_number + 1
	var remaining := AbilityRuntime.remaining_cooldown(abi,session.ability_scheduler.cooldowns_by_combatant.get(session.player_id,{}),next_round)
	_check(not next_options.is_empty() and int(next_options[0].get("cooldown_remaining",-1)) == remaining and remaining > 0 and not bool(next_options[0].get("available",true)),abi + ":cooldown_blocks_next_round")
	print("APPROVED_ABI_RUNTIME_CASE=CHECKED ",abi," outcome=",final_outcome,
		" MH=",ordinary_mh," OH=",ordinary_oh,
		" ABI_hits=",ability_attacks," EFF=",effect_events)

func _test_axe_preflight(abi: String) -> void:
	var session := _fixture(abi)
	if session == null:
		return
	var slots := session.player_ability_options()
	_check(not slots.is_empty() and not bool(slots[0].get("available",true)),abi + ":condition_hidden_without_stacks")
	var ap := session.fighter(true).action_points
	var round_number := session.state.round_number
	var event_id := session.state.next_event_id
	var result := session.play_round(_attacks(session),_blocks(session),abi)
	_check(not bool(result.get("ok",false)) and String(result.get("reason","")) == "axe_condition_unavailable",
		abi + ":atomic_preflight_rejection")
	_check(session.state.round_number == round_number and session.state.next_event_id == event_id and session.fighter(true).action_points == ap,
		abi + ":rejected_cast_does_not_mutate_round")

func _test_trigger_preflight(abi: String) -> void:
	var session := _fixture(abi)
	if session == null:
		return
	var slots := session.player_ability_options()
	_check(not slots.is_empty() and not bool(slots[0].get("available",true)),abi + ":previous_round_trigger_required")
	var round_number := session.state.round_number
	var event_id := session.state.next_event_id
	var ap := session.fighter(true).action_points
	var result := session.play_round(_attacks(session),_blocks(session),abi)
	_check(not bool(result.get("ok",false)) and String(result.get("reason","")) == "abi_trigger_unavailable",
		abi + ":trigger_rejected_before_turn")
	_check(session.state.round_number == round_number and session.state.next_event_id == event_id and session.fighter(true).action_points == ap,
		abi + ":missing_trigger_is_atomic")

func _test_low_ap_preflight(abi: String) -> void:
	var session := _fixture(abi)
	if session == null:
		return
	session.fighter(true).action_points = 1
	var slots := session.player_ability_options()
	_check(not slots.is_empty() and not bool(slots[0].get("available",true)),abi + ":insufficient_ap_disables_button")
	var round_number := session.state.round_number
	var event_id := session.state.next_event_id
	var result := session.play_round(_attacks(session),_blocks(session),abi)
	_check(not bool(result.get("ok",false)) and String(result.get("reason","")) == "insufficient_ap",
		abi + ":insufficient_ap_rejected")
	_check(session.state.round_number == round_number and session.state.next_event_id == event_id and session.fighter(true).action_points == 1,
		abi + ":insufficient_ap_atomic")

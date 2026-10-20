extends SceneTree

## Two-party Arena regression: player and NPC both use their own healing ABI
## in the very same round as ordinary attacks. Next round autonomous EFF003
## DoT and EFF004 HoT tick at end_round and appear in the actual combat journal.
func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ARENA_SUPPORT_HERO", "Arena Support Hero", 5)
	var chest: Dictionary = {
		"instance_id": "ARENA_SUPPORT_CHEST",
		"equip_slots": ["chest"],
		"slot_usage": ["chest"],
		"abilities": ["ABI004"]
	}
	ItemDurabilityService.initialize_item(chest, 100)
	if not repository.add_item(chest) or not hero.receive_item("ARENA_SUPPORT_CHEST",repository) or not hero.equip("chest","ARENA_SUPPORT_CHEST",repository):
		_finish(false,"chest_abi_fixture")
		return
	var session := ArenaCombatSession.new(hero, repository)
	var player := session.fighter(true)
	var npc := session.fighter(false)
	player.max_mana = 100
	player.mana = 100
	npc.max_mana = 100
	npc.mana = 100
	player.hp = maxi(1, int(floor(float(player.max_hp) / 2.0)))
	npc.hp = npc.max_hp - 150
	# The NPC's scheduler intentionally uses a fixture-assigned ability. No
	# separate NPC combat logic may be used for the automatic cast.
	session.ability_scheduler.loadouts[ArenaCombatSession.ENEMY_ID] = ["ABI004"]
	var options: Array[Dictionary] = session.player_ability_options()
	if options.size() != 5 or String(options[3].get("id","")) != "ABI004" or not bool(options[4].get("available",false)):
		_finish(false,"chest_ability_option")
		return
	if String(options[4].get("target_id","")) != session.player_id:
		_finish(false,"support_targets_owner")
		return
	var blocks: Array[String] = []
	for zone in ["chest","arms","waist","legs"]:
		if blocks.size() < CombatModifierService.manual_block_zone_capacity(player):
			blocks.append(zone)
	var first: Dictionary = session.play_round(["chest"],blocks,"ABI004")
	if not bool(first.get("ok",false)):
		_finish(false,"first_round_"+String(first.get("reason","")))
		return
	var player_abi := 0
	var npc_abi := 0
	var physical_player := 0
	var physical_npc := 0
	for event in session.state.event_log:
		if int(event.payload.get("round",-1)) != 1:
			continue
		if event.kind == CombatEvent.Kind.ACTION and String(event.payload.get("ability_id","")) == "ABI004":
			if event.source_id == session.player_id: player_abi += 1
			if event.source_id == ArenaCombatSession.ENEMY_ID: npc_abi += 1
		elif event.kind == CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)):
			if event.source_id == session.player_id: physical_player += 1
			if event.source_id == ArenaCombatSession.ENEMY_ID: physical_npc += 1
	var heal_lines := 0
	for line in Array(first.get("lines",[])):
		if String(line).contains("ABI «Healing»") and String(line).contains("+"):
			heal_lines += 1
	if player_abi != 1 or npc_abi != 1 or physical_player < 1 or physical_npc < 1 or heal_lines != 2:
		_finish(false,"peer_casts_player_"+str(player_abi)+"_npc_"+str(npc_abi)+"_attacks_"+str(physical_player)+"_"+str(physical_npc)+"_logs_"+str(heal_lines))
		return
	if player.is_death_finalized() or npc.is_death_finalized():
		_finish(false,"death_before_tick")
		return
	# The first heal attaches EFF004. A new burning EFF003 is a fixture of
	# autonomous damage, not an additional selected ABI.
	var regen_found := false
	for active in player.active_effects:
		if String(active.get("effect_id","")) == "EFF004":
			regen_found = true
	if not regen_found:
		_finish(false,"heal_abi_did_not_attach_hot")
		return
	npc.active_effects.append({
		"effect_id":"EFF003",
		"definition":EffectCatalog.definition(EffectCatalog.load_json(),"EFF003"),
		"source_id":session.player_id,
		"start_round":session.state.round_number+1,
		"remaining_rounds":2,
		"stacks":1,
		"active_stacks":1
	})
	var second: Dictionary = session.play_round(["chest"],blocks)
	if not bool(second.get("ok",false)):
		_finish(false,"second_round_"+String(second.get("reason","")))
		return
	var dot_log := false
	var hot_log := false
	for line in Array(second.get("lines",[])):
		var rendered := String(line)
		if rendered.contains("EFF EFF003") and rendered.contains("урона"):
			dot_log = true
		if rendered.contains("EFF EFF004") and rendered.contains("HP"):
			hot_log = true
	if not dot_log or not hot_log:
		_finish(false,"periodic_events_not_in_journal_"+str(second.get("lines",[])))
		return
	_finish(true,"two_actor_heals_plus_physical_strikes_and_periodic_EFF")

func _finish(ok:bool,reason:String)->void:
	print("ARENA_DUAL_SUPPORT_ROUND_TEST=", "PASS" if ok else "FAIL", " detail=",reason)
	quit(0 if ok else 1)

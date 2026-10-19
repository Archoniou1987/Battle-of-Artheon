extends SceneTree

## Full Arena command integration, not the isolated ABI Lab: equipped MH
## physical strike and selected canonical ABI share one sealed Combat round.
func _init() -> void:
	var repository := ItemRepository.new()
	var hero := CharacterState.new("ARENA_ABI_HERO","Arena Hero",10)
	var sword := {"instance_id":"ARENA-ABI-MH","equip_slots":["main_hand","off_hand"],"slot_usage":["main_hand"],"abilities":["ABI003"],"par_stats":{"PAR057":1},"damage":{"min":3.0,"max":4.0,"type":"slashing"}}
	var offhand := {"instance_id":"ARENA-ABI-OH","equip_slots":["main_hand","off_hand"],"slot_usage":["off_hand"],"abilities":["ABI004"],"par_stats":{"PAR057":1},"damage":{"min":1.0,"max":2.0,"type":"piercing"}}
	for item in [sword,offhand]:
		ItemDurabilityService.initialize_item(item,100)
		if not repository.add_item(item) or not hero.receive_item(String(item["instance_id"]),repository):
			_finish(false,"fixture_equip_inventory")
			return
	if not hero.equip("main_hand","ARENA-ABI-MH",repository) or not hero.equip("off_hand","ARENA-ABI-OH",repository):
		_finish(false,"fixture_equip_slots")
		return
	var session := ArenaCombatSession.new(hero,repository)
	if session.player_ability_slots.size()!=5 or String(session.player_ability_slots[0])!="ABI003":
		_finish(false,"mh_abi_slot")
		return
	var active: Array = Array(session.ability_scheduler.loadouts.get(session.player_id,[]))
	if active.has("ABI004") or active!=["ABI003"]:
		_finish(false,"offhand_excluded")
		return
	var actor := session.fighter(true)
	actor.mana=100
	actor.max_mana=100
	var options:=session.player_ability_options()
	if options.is_empty() or not bool(options[0].get("available",false)):
		_finish(false,"mh_abi_available")
		return
	var block_count:=CombatModifierService.manual_block_zone_capacity(actor)
	var candidate_blocks:Array[String]=["chest","arms","waist","legs"]
	var blocks:Array[String]=[]
	for i in range(block_count):
		blocks.append(candidate_blocks[i])
	var initial_mana:=actor.mana
	var initial_round:=session.state.round_number
	var wrong:=session.play_round(["chest","arms"],blocks,"ABI004")
	if bool(wrong.get("ok",true)) or actor.mana!=initial_mana or session.state.round_number!=initial_round or not session.state.pending_events.is_empty():
		_finish(false,"offhand_ability_must_reject_atomically")
		return
	# Real submit: two independent MH/OH physical strikes + one Fireball.
	var result:=session.play_round(["head","legs"],blocks,"ABI003")
	if not bool(result.get("ok",false)):
		_finish(false,"round_rejected_"+String(result.get("reason","")))
		return
	var physical:=0
	var casts:=0
	var weapons:Array[int]=[]
	for event in session.state.event_log:
		if event.source_id!=session.player_id or int(event.payload.get("round",-1))!=1:
			continue
		if event.kind==CombatEvent.Kind.ATTACK and bool(event.payload.get("is_weapon_attack",false)) and not bool(event.payload.get("is_counterattack",false)):
			physical+=1
			weapons.append(int(event.payload.get("weapon_index",-1)))
		elif event.kind==CombatEvent.Kind.ACTION and String(event.payload.get("ability_id",""))=="ABI003":
			casts+=1
	var mana_cost:=int(AbilityCatalog.definition(session.ability_scheduler.definitions,"ABI003").get("mana_cost",0))
	if physical!=2 or casts!=1 or not weapons.has(0) or not weapons.has(1) or actor.mana!=initial_mana-mana_cost:
		_finish(false,"three_actions_physical_"+str(physical)+"_abi_"+str(casts)+"_mana_"+str(actor.mana))
		return
	var after_round:=session.state.round_number
	var after_mana:=actor.mana
	var duplicate:=session.play_round(["chest","chest"],blocks,"ABI003")
	if bool(duplicate.get("ok",true)) or session.state.round_number!=after_round or actor.mana!=after_mana:
		_finish(false,"cooldown_rejects_before_round")
		return
	_finish(true,"two_weapon_strikes_plus_one_abi")

func _finish(passed:bool,detail:String)->void:
	print("ARENA_ABILITY_INTEGRATION_TEST=", "PASS" if passed else "FAIL", " detail=",detail)
	quit(0 if passed else 1)
